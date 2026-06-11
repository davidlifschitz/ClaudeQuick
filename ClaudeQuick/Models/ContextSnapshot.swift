import Foundation

struct ContextSnapshot: Codable {
    let id: UUID
    let messageId: UUID
    let contextWindowUsed: Int
    let tokensUsed: Int
    let modelVersion: String
    let timestamp: Date
    let metadata: [String: String]?

    init(
        id: UUID = UUID(),
        messageId: UUID,
        contextWindowUsed: Int,
        tokensUsed: Int,
        modelVersion: String,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.contextWindowUsed = contextWindowUsed
        self.tokensUsed = tokensUsed
        self.modelVersion = modelVersion
        self.timestamp = timestamp
        self.metadata = metadata
    }
}
