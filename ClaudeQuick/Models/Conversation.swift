import Foundation

struct Conversation: Codable, Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messageCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
    }
}
