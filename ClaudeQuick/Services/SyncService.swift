import Foundation
import CloudKit

enum SyncServiceError: Error {
    case cloudKitUnavailable
    case syncInProgress
    case recordFetchFailed(String)
    case recordSaveFailed(String)
    case containerUnavailable
    case invalidRecord
    case networkError(String)
}

class SyncService {
    static let shared = SyncService()

    private let container: CKContainer
    private let database: CKDatabase
    private var syncInProgress = false
    private var lastSyncDate: Date?

    // MARK: - Record Type Constants

    private let conversationRecordType = "Conversation"
    private let messageRecordType = "Message"

    // MARK: - Initialization

    init(containerIdentifier: String = "iCloud.com.claudequick.app") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    // MARK: - Sync Status

    func isSyncAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    func getLastSyncDate() -> Date? {
        return lastSyncDate
    }

    // MARK: - Conversation Sync

    func syncConversation(_ conversation: Conversation) async throws {
        guard !syncInProgress else { throw SyncServiceError.syncInProgress }
        guard isSyncAvailable() else { throw SyncServiceError.cloudKitUnavailable }

        syncInProgress = true
        defer { syncInProgress = false }

        let record = CKRecord(
            recordType: conversationRecordType,
            recordID: CKRecord.ID(recordName: conversation.id.uuidString)
        )

        record["title"] = conversation.title
        record["createdAt"] = conversation.createdAt
        record["updatedAt"] = conversation.updatedAt
        record["messageCount"] = conversation.messageCount

        do {
            _ = try await database.save(record)
            lastSyncDate = Date()
        } catch {
            throw SyncServiceError.recordSaveFailed("Failed to save conversation: \(error.localizedDescription)")
        }
    }

    func fetchConversationFromCloud(id: UUID) async throws -> Conversation? {
        guard isSyncAvailable() else { throw SyncServiceError.cloudKitUnavailable }

        let recordID = CKRecord.ID(recordName: id.uuidString)

        do {
            let record = try await database.record(for: recordID)
            return parseConversationRecord(record)
        } catch {
            if (error as? CKError)?.code == .unknownItem {
                return nil
            }
            throw SyncServiceError.recordFetchFailed("Failed to fetch conversation: \(error.localizedDescription)")
        }
    }

    func deleteConversationFromCloud(id: UUID) async throws {
        guard !syncInProgress else { throw SyncServiceError.syncInProgress }
        guard isSyncAvailable() else { throw SyncServiceError.cloudKitUnavailable }

        syncInProgress = true
        defer { syncInProgress = false }

        let recordID = CKRecord.ID(recordName: id.uuidString)

        do {
            _ = try await database.deleteRecord(withID: recordID)
            lastSyncDate = Date()
        } catch {
            throw SyncServiceError.recordSaveFailed("Failed to delete conversation: \(error.localizedDescription)")
        }
    }

    // MARK: - Message Sync

    func syncMessage(_ message: Message) async throws {
        guard !syncInProgress else { throw SyncServiceError.syncInProgress }
        guard isSyncAvailable() else { throw SyncServiceError.cloudKitUnavailable }

        syncInProgress = true
        defer { syncInProgress = false }

        let record = CKRecord(
            recordType: messageRecordType,
            recordID: CKRecord.ID(recordName: message.id.uuidString)
        )

        record["conversationId"] = message.conversationId.uuidString
        record["role"] = message.role.rawValue
        record["content"] = message.content
        record["timestamp"] = message.timestamp

        if let contextSnapshot = message.contextSnapshot {
            let encoder = JSONEncoder()
            if let jsonData = try? encoder.encode(contextSnapshot),
               let jsonString = String(data: jsonData, encoding: .utf8)
            {
                record["contextSnapshot"] = jsonString
            }
        }

        do {
            _ = try await database.save(record)
            lastSyncDate = Date()
        } catch {
            throw SyncServiceError.recordSaveFailed("Failed to save message: \(error.localizedDescription)")
        }
    }

    func fetchMessagesFromCloud(for conversationId: UUID) async throws -> [Message] {
        guard isSyncAvailable() else { throw SyncServiceError.cloudKitUnavailable }

        let predicate = NSPredicate(format: "conversationId == %@", conversationId.uuidString)
        let query = CKQuery(recordType: messageRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        do {
            let records = try await database.records(matching: query)
            return records.matchResults.compactMap { result in
                switch result.1 {
                case .success(let record):
                    return parseMessageRecord(record)
                case .failure:
                    return nil
                }
            }
        } catch {
            throw SyncServiceError.recordFetchFailed("Failed to fetch messages: \(error.localizedDescription)")
        }
    }

    func deleteMessageFromCloud(id: UUID) async throws {
        guard !syncInProgress else { throw SyncServiceError.syncInProgress }
        guard isSyncAvailable() else { throw SyncServiceError.cloudKitUnavailable }

        syncInProgress = true
        defer { syncInProgress = false }

        let recordID = CKRecord.ID(recordName: id.uuidString)

        do {
            _ = try await database.deleteRecord(withID: recordID)
            lastSyncDate = Date()
        } catch {
            throw SyncServiceError.recordSaveFailed("Failed to delete message: \(error.localizedDescription)")
        }
    }

    // MARK: - Record Parsing

    private func parseConversationRecord(_ record: CKRecord) -> Conversation? {
        guard let title = record["title"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date,
              let messageCount = record["messageCount"] as? Int
        else {
            return nil
        }

        guard let id = UUID(uuidString: record.recordID.recordName) else {
            return nil
        }

        return Conversation(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messageCount
        )
    }

    private func parseMessageRecord(_ record: CKRecord) -> Message? {
        guard let conversationIdStr = record["conversationId"] as? String,
              let conversationId = UUID(uuidString: conversationIdStr),
              let roleStr = record["role"] as? String,
              let role = MessageRole(rawValue: roleStr),
              let content = record["content"] as? String,
              let timestamp = record["timestamp"] as? Date
        else {
            return nil
        }

        guard let id = UUID(uuidString: record.recordID.recordName) else {
            return nil
        }

        var contextSnapshot: ContextSnapshot?
        if let contextSnapshotJSON = record["contextSnapshot"] as? String,
           let jsonData = contextSnapshotJSON.data(using: .utf8)
        {
            let decoder = JSONDecoder()
            contextSnapshot = try? decoder.decode(ContextSnapshot.self, from: jsonData)
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
