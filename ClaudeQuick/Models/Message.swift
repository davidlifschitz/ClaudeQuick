import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct Message: Codable, Identifiable {
    let id: UUID
    let conversationId: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var contextSnapshot: ContextSnapshot?

    init(
        id: UUID = UUID(),
        conversationId: UUID,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        contextSnapshot: ContextSnapshot? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextSnapshot = contextSnapshot
    }
}
