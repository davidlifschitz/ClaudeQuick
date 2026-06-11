import Foundation

// MARK: - Request

struct MessageRequest: Codable {
    let role: String
    let content: String
}

struct AnthropicRequest: Codable {
    let model: String
    let messages: [MessageRequest]
    let max_tokens: Int
    let temperature: Double?
    let stream: Bool?
}

// MARK: - Response

struct AnthropicResponse: Codable {
    let id: String
    let type: String
    let role: String?
    let content: [ContentBlock]
    let model: String
    let stop_reason: String?
    let usage: AnthropicUsage?

    var textContent: String {
        content.compactMap { $0.text }.joined()
    }
}

struct ContentBlock: Codable {
    let type: String
    let text: String?
}

struct AnthropicUsage: Codable {
    let input_tokens: Int
    let output_tokens: Int
}

// MARK: - Streaming

struct StreamEvent: Codable {
    let type: String
    let index: Int?
    let delta: StreamDelta?
    let usage: AnthropicUsage?
}

struct StreamDelta: Codable {
    let type: String
    let text: String?
}

// MARK: - Error

struct APIError: Codable {
    let type: String
    let error: ErrorDetail
}

struct ErrorDetail: Codable {
    let type: String
    let message: String
}
