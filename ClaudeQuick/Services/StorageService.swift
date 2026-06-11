import Foundation

#if os(macOS)
import FMDB
#else
// For testing without FMDB
#endif

enum StorageServiceError: Error {
    case initializationFailed
    case databaseError(String)
    case notFound
    case encodingFailed
    case decodingFailed
}

class StorageService {
    static let shared = StorageService(dbPath: StorageService.defaultDatabasePath())

    private var db: FMDatabase?
    private let dbPath: String
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(dbPath: String) {
        self.dbPath = dbPath
        setupDatabase()
    }

    static func defaultDatabasePath() -> String {
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory,
            .userDomainMask,
            true
        )[0]
        let appSupportPath = (documentsPath as NSString).appendingPathComponent("ClaudeQuick")

        try? FileManager.default.createDirectory(
            atPath: appSupportPath,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return (appSupportPath as NSString).appendingPathComponent("claudequick.db")
    }

    // MARK: - Database Setup

    private func setupDatabase() {
        db = FMDatabase(path: dbPath)

        guard let db = db, db.open() else {
            print("Failed to open database")
            return
        }

        db.shouldCacheStatements = true

        do {
            try createTables()
        } catch {
            print("Failed to create tables: \(error)")
        }
    }

    private func createTables() throws {
        guard let db = db else { throw StorageServiceError.initializationFailed }

        let conversationTableSQL = """
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                messageCount INTEGER NOT NULL DEFAULT 0
            )
        """

        let messageTableSQL = """
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                conversationId TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                contextSnapshotJSON TEXT,
                FOREIGN KEY(conversationId) REFERENCES conversations(id) ON DELETE CASCADE
            )
        """

        let contextSnapshotTableSQL = """
            CREATE TABLE IF NOT EXISTS contextSnapshots (
                id TEXT PRIMARY KEY,
                messageId TEXT NOT NULL,
                contextWindowUsed INTEGER NOT NULL,
                tokensUsed INTEGER NOT NULL,
                modelVersion TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                metadataJSON TEXT,
                FOREIGN KEY(messageId) REFERENCES messages(id) ON DELETE CASCADE
            )
        """

        if !db.executeStatements(conversationTableSQL) {
            throw StorageServiceError.databaseError("Failed to create conversations table")
        }

        if !db.executeStatements(messageTableSQL) {
            throw StorageServiceError.databaseError("Failed to create messages table")
        }

        if !db.executeStatements(contextSnapshotTableSQL) {
            throw StorageServiceError.databaseError("Failed to create contextSnapshots table")
        }
    }

    // MARK: - Conversation Operations

    func saveConversation(_ conversation: Conversation) throws {
        guard let db = db else { throw StorageServiceError.initializationFailed }

        let dateFormatter = ISO8601DateFormatter()
        let createdAtStr = dateFormatter.string(from: conversation.createdAt)
        let updatedAtStr = dateFormatter.string(from: conversation.updatedAt)

        let insertSQL = """
            INSERT OR REPLACE INTO conversations (id, title, createdAt, updatedAt, messageCount)
            VALUES (?, ?, ?, ?, ?)
        """

        guard db.executeUpdate(
            insertSQL,
            withArgumentsIn: [
                conversation.id.uuidString,
                conversation.title,
                createdAtStr,
                updatedAtStr,
                conversation.messageCount,
            ]
        ) else {
            throw StorageServiceError.databaseError("Failed to save conversation: \(db.lastError())")
        }
    }

    func fetchConversation(id: UUID) throws -> Conversation? {
        guard let db = db else { throw StorageServiceError.initializationFailed }

        let query = "SELECT * FROM conversations WHERE id = ?"
        guard let resultSet = db.executeQuery(query, withArgumentsIn: [id.uuidString]) else {
            throw StorageServiceError.databaseError("Query failed: \(db.lastError())")
        }

        defer { resultSet.close() }

        if resultSet.next() {
            return parseConversationRow(resultSet)
        }

        return nil
    }

    func fetchAllConversations() throws -> [Conversation] {
        guard let db = db else { throw StorageServiceError.initializationFailed }

        let query = "SELECT * FROM conversations ORDER BY updatedAt DESC"
        guard let resultSet = db.executeQuery(query, withArgumentsIn: []) else {
            throw StorageServiceError.databaseError("Query failed: \(db.lastError())")
        }

        defer { resultSet.close() }

        var conversations: [Conversation] = []
        while resultSet.next() {
            if let conversation = parseConversationRow(resultSet) {
                conversations.append(conversation)
            }
        }

        return conversations
    }

    func deleteConversation(id: UUID) throws {
        guard let db = db else { throw StorageServiceError.initializationFailed }

        let deleteSQL = "DELETE FROM conversations WHERE id = ?"
        guard db.executeUpdate(deleteSQL, withArgumentsIn: [id.uuidString]) else {
            throw StorageServiceError.databaseError("Failed to delete conversation: \(db.lastError())")
        }
    }

    // MARK: - Message Operations

    func saveMessage(_ message: Message) throws {
        guard let db = db else { throw StorageServiceError.initializationFailed }

        let dateFormatter = ISO8601DateFormatter()
        let timestampStr = dateFormatter.string(from: message.timestamp)

        var contextSnapshotJSON: String?
        if let contextSnapshot = message.contextSnapshot {
            contextSnapshotJSON = String(
                data: try jsonEncoder.encode(contextSnapshot),
                encoding: .utf8
            )
        }

        let insertSQL = """
            INSERT OR REPLACE INTO messages (id, conversationId, role, content, timestamp, contextSnapshotJSON)
            VALUES (?, ?, ?, ?, ?, ?)
        """

        guard db.executeUpdate(
            insertSQL,
            withArgumentsIn: [
                message.id.uuidString,
                message.conversationId.uuidString,
                message.role.rawValue,
                message.content,
                timestampStr,
                contextSnapshotJSON as Any,
            ]
        ) else {
            throw StorageServiceError.databaseError("Failed to save message: \(db.lastError())")
        }
    }

    func fetchMessages(for conversationId: UUID) throws -> [Message] {
        guard let db = db else { throw StorageServiceError.initializationFailed }

        let query = "SELECT * FROM messages WHERE conversationId = ? ORDER BY timestamp ASC"
        guard let resultSet = db.executeQuery(query, withArgumentsIn: [conversationId.uuidString])
        else {
            throw StorageServiceError.databaseError("Query failed: \(db.lastError())")
        }

        defer { resultSet.close() }

        var messages: [Message] = []
        while resultSet.next() {
            if let message = parseMessageRow(resultSet) {
                messages.append(message)
            }
        }

        return messages
    }

    func deleteMessage(id: UUID) throws {
        guard let db = db else { throw StorageServiceError.initializationFailed }

        let deleteSQL = "DELETE FROM messages WHERE id = ?"
        guard db.executeUpdate(deleteSQL, withArgumentsIn: [id.uuidString]) else {
            throw StorageServiceError.databaseError("Failed to delete message: \(db.lastError())")
        }
    }

    // MARK: - Helper Methods

    private func parseConversationRow(_ resultSet: FMResultSet) -> Conversation? {
        let dateFormatter = ISO8601DateFormatter()

        guard let idStr = resultSet.string(forColumn: "id"),
              let id = UUID(uuidString: idStr),
              let title = resultSet.string(forColumn: "title"),
              let createdAtStr = resultSet.string(forColumn: "createdAt"),
              let createdAt = dateFormatter.date(from: createdAtStr),
              let updatedAtStr = resultSet.string(forColumn: "updatedAt"),
              let updatedAt = dateFormatter.date(from: updatedAtStr)
        else {
            return nil
        }

        let messageCount = Int(resultSet.long(forColumn: "messageCount"))

        return Conversation(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messageCount
        )
    }

    private func parseMessageRow(_ resultSet: FMResultSet) -> Message? {
        let dateFormatter = ISO8601DateFormatter()

        guard let idStr = resultSet.string(forColumn: "id"),
              let id = UUID(uuidString: idStr),
              let conversationIdStr = resultSet.string(forColumn: "conversationId"),
              let conversationId = UUID(uuidString: conversationIdStr),
              let roleStr = resultSet.string(forColumn: "role"),
              let role = MessageRole(rawValue: roleStr),
              let content = resultSet.string(forColumn: "content"),
              let timestampStr = resultSet.string(forColumn: "timestamp"),
              let timestamp = dateFormatter.date(from: timestampStr)
        else {
            return nil
        }

        var contextSnapshot: ContextSnapshot?
        if let contextSnapshotJSON = resultSet.string(forColumn: "contextSnapshotJSON"),
           let jsonData = contextSnapshotJSON.data(using: .utf8)
        {
            contextSnapshot = try? jsonDecoder.decode(ContextSnapshot.self, from: jsonData)
        }

        return Message(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            timestamp: timestamp,
            contextSnapshot: contextSnapshot
        )
    }
}
