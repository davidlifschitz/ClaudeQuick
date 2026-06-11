import Foundation

class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL = "https://api.anthropic.com"
    private var apiKey: String?

    init(session: URLSession = URLSession.shared) {
        self.session = session
        loadAPIKey()
    }

    private func loadAPIKey() {
        apiKey = KeychainService.shared.retrieve(key: "anthropic_api_key")
    }

    func setAPIKey(_ key: String) throws {
        apiKey = key
        try KeychainService.shared.save(key: "anthropic_api_key", value: key)
    }

    // MARK: - Synchronous API Call

    func sendMessage(
        messages: [MessageRequest],
        model: String = "claude-3-5-sonnet-20241022",
        maxTokens: Int = 1024,
        temperature: Double = 0.7
    ) async throws -> ChatCompletionResponse {
        guard let apiKey = apiKey else {
            throw NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key not set"])
        }

        let request = ChatCompletionRequest(
            model: model,
            messages: messages,
            max_tokens: maxTokens,
            temperature: temperature,
            stream: false
        )

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            let decoder = JSONDecoder()
            if let errorResponse = try? decoder.decode(APIError.self, from: data) {
                throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            }
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }

        let decoder = JSONDecoder()
        let chatCompletion = try decoder.decode(ChatCompletionResponse.self, from: data)

        // Track token usage
        if let usage = chatCompletion.usage {
            try CostTracker.shared.trackUsage(
                model: model,
                inputTokens: usage.prompt_tokens,
                outputTokens: usage.completion_tokens
            )
        }

        return chatCompletion
    }

    // MARK: - Streaming API Call

    func streamMessage(
        messages: [MessageRequest],
        model: String = "claude-3-5-sonnet-20241022",
        maxTokens: Int = 1024,
        temperature: Double = 0.7,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let apiKey = apiKey else {
            onComplete(.failure(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key not set"])))
            return
        }

        let request = ChatCompletionRequest(
            model: model,
            messages: messages,
            max_tokens: maxTokens,
            temperature: temperature,
            stream: true
        )

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            onComplete(.failure(error))
            return
        }

        var totalTokens = 0
        var inputTokens = 0

        let task = session.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                onComplete(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                onComplete(.failure(NSError(domain: "APIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }

            if httpResponse.statusCode != 200 {
                if let data = data {
                    let decoder = JSONDecoder()
                    if let errorResponse = try? decoder.decode(APIError.self, from: data) {
                        onComplete(.failure(NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])))
                        return
                    }
                }
                onComplete(.failure(NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])))
                return
            }

            guard let data = data else {
                onComplete(.failure(NSError(domain: "APIClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }

            let lines = String(data: data, encoding: .utf8)?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init) ?? []

            let decoder = JSONDecoder()

            for line in lines {
                guard line.hasPrefix("data: ") else { continue }

                let jsonString = String(line.dropFirst(6))

                do {
                    if jsonString == "[DONE]" {
                        break
                    }

                    let response = try decoder.decode(ChatCompletionResponse.self, from: jsonString.data(using: .utf8) ?? Data())

                    if let choice = response.choices.first, let delta = choice.delta {
                        if let content = delta.content {
                            onChunk(content)
                        }
                    }

                    if let usage = response.usage {
                        totalTokens = usage.total_tokens
                        inputTokens = usage.prompt_tokens
                    }
                } catch {
                    // Continue on parse error
                }
            }

            do {
                if totalTokens > 0 {
                    try CostTracker.shared.trackUsage(
                        model: model,
                        inputTokens: inputTokens,
                        outputTokens: totalTokens - inputTokens
                    )
                }
            } catch {
                // Log error but don't fail
            }

            onComplete(.success(()))
        }

        task.resume()
    }

    // MARK: - Streaming API Call with Retry Logic

    func streamMessageWithRetry(
        messages: [MessageRequest],
        model: String = "claude-3-5-sonnet-20241022",
        maxTokens: Int = 1024,
        temperature: Double = 0.7,
        maxRetries: Int = 3,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        streamMessageWithRetryHelper(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            maxRetries: maxRetries,
            currentAttempt: 0,
            onChunk: onChunk,
            onComplete: onComplete
        )
    }

    private func streamMessageWithRetryHelper(
        messages: [MessageRequest],
        model: String,
        maxTokens: Int,
        temperature: Double,
        maxRetries: Int,
        currentAttempt: Int,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        streamMessage(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            onChunk: onChunk
        ) { [weak self] result in
            switch result {
            case .success:
                onComplete(.success(()))
            case .failure(let error):
                let nsError = error as NSError

                // Determine if error is retryable (network errors, server 5xx errors, timeout)
                let isRetryable = nsError.domain == NSURLErrorDomain ||
                    (nsError.domain == "APIClient" && (nsError.code >= 500 || nsError.code == -1001)) ||
                    nsError.code == NSURLErrorTimedOut ||
                    nsError.code == NSURLErrorNetworkConnectionLost ||
                    nsError.code == NSURLErrorNotConnectedToInternet

                if isRetryable && currentAttempt < maxRetries {
                    // Calculate exponential backoff: 2^attempt seconds (1s, 2s, 4s)
                    let delaySeconds = Double(1 << currentAttempt)

                    DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                        self?.streamMessageWithRetryHelper(
                            messages: messages,
                            model: model,
                            maxTokens: maxTokens,
                            temperature: temperature,
                            maxRetries: maxRetries,
                            currentAttempt: currentAttempt + 1,
                            onChunk: onChunk,
                            onComplete: onComplete
                        )
                    }
                } else {
                    onComplete(.failure(error))
                }
            }
        }
    }
}
