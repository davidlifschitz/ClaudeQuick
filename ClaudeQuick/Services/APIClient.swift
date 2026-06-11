import Foundation

class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL = "https://api.anthropic.com"
    private var apiKey: String?
    private var oauthToken: String?

    var isAuthenticated: Bool { apiKey != nil || oauthToken != nil }

    init(session: URLSession = URLSession.shared) {
        self.session = session
        loadCredentials()
    }

    private func loadCredentials() {
        if let key = try? KeychainService.shared.retrieveAPIKey(for: "anthropic") {
            apiKey = key
            return
        }
        if let creds = try? KeychainService.shared.readClaudeCodeCredentials(), !creds.isExpired {
            oauthToken = creds.accessToken
        }
    }

    func setAPIKey(_ key: String) throws {
        apiKey = key
        oauthToken = nil
        try KeychainService.shared.saveAPIKey(key, for: "anthropic")
    }

    func setOAuthToken(_ token: String) {
        oauthToken = token
        apiKey = nil
    }

    private func applyAuth(to request: inout URLRequest) throws {
        if let key = apiKey {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        } else if let token = oauthToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
    }

    private func makeRequest(model: String, messages: [MessageRequest], maxTokens: Int, temperature: Double, stream: Bool) throws -> URLRequest {
        let body = AnthropicRequest(
            model: model,
            messages: messages,
            max_tokens: maxTokens,
            temperature: temperature,
            stream: stream ? true : nil
        )

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        try applyAuth(to: &urlRequest)
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    // MARK: - Send Message

    func sendMessage(
        messages: [MessageRequest],
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 1024,
        temperature: Double = 0.7
    ) async throws -> AnthropicResponse {
        let urlRequest = try makeRequest(model: model, messages: messages, maxTokens: maxTokens, temperature: temperature, stream: false)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(APIError.self, from: data) {
                throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            }
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "")"])
        }

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        if let usage = result.usage {
            try CostTracker.shared.trackUsage(model: model, inputTokens: usage.input_tokens, outputTokens: usage.output_tokens)
        }

        return result
    }

    // MARK: - Streaming

    func streamMessage(
        messages: [MessageRequest],
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 1024,
        temperature: Double = 0.7,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let urlRequest = try? makeRequest(model: model, messages: messages, maxTokens: maxTokens, temperature: temperature, stream: true) else {
            onComplete(.failure(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to build request"])))
            return
        }

        var inputTokens = 0
        var outputTokens = 0

        let task = session.dataTask(with: urlRequest) { data, response, error in
            if let error = error { onComplete(.failure(error)); return }

            guard let httpResponse = response as? HTTPURLResponse else {
                onComplete(.failure(NSError(domain: "APIClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }

            if httpResponse.statusCode != 200 {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                onComplete(.failure(NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])))
                return
            }

            guard let data = data else {
                onComplete(.failure(NSError(domain: "APIClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }

            let decoder = JSONDecoder()
            let lines = String(data: data, encoding: .utf8)?
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("data: ") } ?? []

            for line in lines {
                let json = String(line.dropFirst(6))
                guard json != "[DONE]", !json.isEmpty,
                      let eventData = json.data(using: .utf8),
                      let event = try? decoder.decode(StreamEvent.self, from: eventData)
                else { continue }

                if event.type == "content_block_delta", let text = event.delta?.text {
                    onChunk(text)
                }
                if event.type == "message_delta", let usage = event.usage {
                    outputTokens = usage.output_tokens
                }
                if event.type == "message_start", let usage = event.usage {
                    inputTokens = usage.input_tokens
                }
            }

            if outputTokens > 0 {
                try? CostTracker.shared.trackUsage(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
            }
            onComplete(.success(()))
        }
        task.resume()
    }

    // MARK: - Streaming with Retry

    func streamMessageWithRetry(
        messages: [MessageRequest],
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 1024,
        temperature: Double = 0.7,
        maxRetries: Int = 3,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        streamMessageWithRetryHelper(messages: messages, model: model, maxTokens: maxTokens, temperature: temperature, maxRetries: maxRetries, currentAttempt: 0, onChunk: onChunk, onComplete: onComplete)
    }

    private func streamMessageWithRetryHelper(
        messages: [MessageRequest], model: String, maxTokens: Int, temperature: Double,
        maxRetries: Int, currentAttempt: Int,
        onChunk: @escaping (String) -> Void, onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        streamMessage(messages: messages, model: model, maxTokens: maxTokens, temperature: temperature, onChunk: onChunk) { [weak self] result in
            switch result {
            case .success: onComplete(.success(()))
            case .failure(let error):
                let nsError = error as NSError
                let isRetryable = nsError.domain == NSURLErrorDomain || (nsError.code >= 500)
                if isRetryable && currentAttempt < maxRetries {
                    let delay = Double(1 << currentAttempt)
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.streamMessageWithRetryHelper(messages: messages, model: model, maxTokens: maxTokens, temperature: temperature, maxRetries: maxRetries, currentAttempt: currentAttempt + 1, onChunk: onChunk, onComplete: onComplete)
                    }
                } else {
                    onComplete(.failure(error))
                }
            }
        }
    }
}
