import XCTest

class StorageServiceTests: XCTestCase {
    var storageService: StorageService!
    var testDBPath: String!

    override func setUp() {
        super.setUp()

        // Use a temporary database for testing
        let tempDir = NSTemporaryDirectory()
        testDBPath = (tempDir as NSString).appendingPathComponent("test_claudequick.db")

        // Remove the test database if it exists
        try? FileManager.default.removeItem(atPath: testDBPath)

        storageService = StorageService(dbPath: testDBPath)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: testDBPath)
    }

    // MARK: - Conversation Tests

    func testSaveAndFetchConversation() throws {
        let conversation = Conversation(title: "Test Conversation")
        try storageService.saveConversation(conversation)

        let fetched = try storageService.fetchConversation(id: conversation.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, conversation.id)
        XCTAssertEqual(fetched?.title, "Test Conversation")
    }

    func testFetchAllConversations() throws {
        let conv1 = Conversation(title: "Conversation 1")
        let conv2 = Conversation(title: "Conversation 2")

        try storageService.saveConversation(conv1)
        try storageService.saveConversation(conv2)

        let allConversations = try storageService.fetchAllConversations()
        XCTAssertEqual(allConversations.count, 2)
    }

    func testDeleteConversation() throws {
        let conversation = Conversation(title: "Test Conversation")
        try storageService.saveConversation(conversation)

        try storageService.deleteConversation(id: conversation.id)

        let fetched = try storageService.fetchConversation(id: conversation.id)
        XCTAssertNil(fetched)
    }

    func testUpdateConversation() throws {
        var conversation = Conversation(title: "Original Title")
        try storageService.saveConversation(conversation)

        conversation.title = "Updated Title"
        conversation.messageCount = 5
        try storageService.saveConversation(conversation)

        let fetched = try storageService.fetchConversation(id: conversation.id)
        XCTAssertEqual(fetched?.title, "Updated Title")
        XCTAssertEqual(fetched?.messageCount, 5)
    }

    // MARK: - Message Tests

    func testSaveAndFetchMessage() throws {
        let conversation = Conversation(title: "Test")
        try storageService.saveConversation(conversation)

        let message = Message(
            conversationId: conversation.id,
            role: .user,
            content: "Hello, Claude!"
        )
        try storageService.saveMessage(message)

        let messages = try storageService.fetchMessages(for: conversation.id)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Hello, Claude!")
        XCTAssertEqual(messages[0].role, .user)
    }

    func testFetchMessagesOrdered() throws {
        let conversation = Conversation(title: "Test")
        try storageService.saveConversation(conversation)

        let message1 = Message(
            conversationId: conversation.id,
            role: .user,
            content: "First message"
        )
        let message2 = Message(
            conversationId: conversation.id,
            role: .assistant,
            content: "Second message"
        )

        try storageService.saveMessage(message1)
        try storageService.saveMessage(message2)

        let messages = try storageService.fetchMessages(for: conversation.id)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].content, "First message")
        XCTAssertEqual(messages[1].content, "Second message")
    }

    func testDeleteMessage() throws {
        let conversation = Conversation(title: "Test")
        try storageService.saveConversation(conversation)

        let message = Message(
            conversationId: conversation.id,
            role: .user,
            content: "Test message"
        )
        try storageService.saveMessage(message)

        try storageService.deleteMessage(id: message.id)

        let messages = try storageService.fetchMessages(for: conversation.id)
        XCTAssertEqual(messages.count, 0)
    }

    func testMessageWithContextSnapshot() throws {
        let conversation = Conversation(title: "Test")
        try storageService.saveConversation(conversation)

        let contextSnapshot = ContextSnapshot(
            messageId: UUID(),
            contextWindowUsed: 2048,
            tokensUsed: 512,
            modelVersion: "claude-3-opus"
        )

        let message = Message(
            conversationId: conversation.id,
            role: .assistant,
            content: "Response with context",
            contextSnapshot: contextSnapshot
        )
        try storageService.saveMessage(message)

        let messages = try storageService.fetchMessages(for: conversation.id)
        XCTAssertEqual(messages.count, 1)
        XCTAssertNotNil(messages[0].contextSnapshot)
        XCTAssertEqual(messages[0].contextSnapshot?.tokensUsed, 512)
        XCTAssertEqual(messages[0].contextSnapshot?.modelVersion, "claude-3-opus")
    }

    // MARK: - Edge Cases

    func testFetchNonexistentConversation() throws {
        let nonexistentId = UUID()
        let fetched = try storageService.fetchConversation(id: nonexistentId)
        XCTAssertNil(fetched)
    }

    func testFetchMessagesForEmptyConversation() throws {
        let conversation = Conversation(title: "Empty")
        try storageService.saveConversation(conversation)

        let messages = try storageService.fetchMessages(for: conversation.id)
        XCTAssertEqual(messages.count, 0)
    }

    func testCascadeDeleteMessages() throws {
        let conversation = Conversation(title: "Test")
        try storageService.saveConversation(conversation)

        let message1 = Message(
            conversationId: conversation.id,
            role: .user,
            content: "Message 1"
        )
        let message2 = Message(
            conversationId: conversation.id,
            role: .assistant,
            content: "Message 2"
        )

        try storageService.saveMessage(message1)
        try storageService.saveMessage(message2)

        try storageService.deleteConversation(id: conversation.id)

        let messages = try storageService.fetchMessages(for: conversation.id)
        XCTAssertEqual(messages.count, 0)
    }
}
