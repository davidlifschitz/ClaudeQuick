import Foundation

// MARK: - API Request Models

struct MessageRequest: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [MessageRequest]
    let max_tokens: Int?
    let temperature: Double?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case max_tokens
        case temperature
        case stream
    }
}

// MARK: - API Response Models

struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?
}

struct Choice: Codable {
    let index: Int
    let message: ResponseMessage?
    let delta: Delta?
    let finish_reason: String?
}

struct ResponseMessage: Codable {
    let role: String
    let content: String
}

struct Delta: Codable {
    let role: String?
    let content: String?
}

struct Usage: Codable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}

struct APIError: Codable {
    let error: ErrorDetail
}

struct ErrorDetail: Codable {
    let message: String
    let type: String
    let param: String?
    let code: String?
}

// MARK: - Streaming Models

struct StreamEvent: Codable {
    let data: String

    var isStreamEnd: Bool {
        return data == "[DONE]"
    }

    func toChatCompletion() throws -> ChatCompletionResponse? {
        guard !isStreamEnd else { return nil }
        let decoder = JSONDecoder()
        return try decoder.decode(ChatCompletionResponse.self, from: data.data(using: .utf8) ?? Data())
    }
}
