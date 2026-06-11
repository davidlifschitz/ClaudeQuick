import SwiftUI
import Foundation

class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var userInput: String = ""
    @Published var isLoading: Bool = false
    @Published var streamingText: String = ""
    @Published var selectedModel: String = "claude-3-5-sonnet-20241022"
    @Published var temperature: Double = 0.7
    @Published var attachedContext: [String] = []
    @Published var errorMessage: String?

    private let storageService = StorageService.shared
    private let apiClient = APIClient.shared
    private let syncService = SyncService.shared
    private let contextExtractor = ContextExtractor.shared
    private let costTracker = CostTracker.shared

    // MARK: - Initialization

    init() {
        loadConversations()
    }

    // MARK: - Conversation Management

    func loadConversations() {
        do {
            conversations = try storageService.loadConversations()
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    func createConversation(title: String = "New Conversation") {
        let conversation = Conversation(title: title)
        do {
            try storageService.saveConversation(conversation)
            currentConversation = conversation
            messages = []
            loadConversations()
        } catch {
            errorMessage = "Failed to create conversation: \(error.localizedDescription)"
        }
    }

    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversation
        loadMessagesForConversation(conversation.id)
    }

    func deleteConversation(_ conversation: Conversation) {
        do {
            try storageService.deleteConversation(conversation.id)
            if currentConversation?.id == conversation.id {
                currentConversation = nil
                messages = []
            }
            loadConversations()
        } catch {
            errorMessage = "Failed to delete conversation: \(error.localizedDescription)"
        }
    }

    func renameConversation(_ conversation: Conversation, newTitle: String) {
        var updated = conversation
        updated.updatedAt = Date()
        do {
            try storageService.updateConversation(updated)
            if currentConversation?.id == conversation.id {
                currentConversation = updated
            }
            loadConversations()
        } catch {
            errorMessage = "Failed to rename conversation: \(error.localizedDescription)"
        }
    }

    // MARK: - Message Management

    func loadMessagesForConversation(_ conversationId: UUID) {
        do {
            messages = try storageService.loadMessages(for: conversationId)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    func sendMessage() {
        guard !userInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let conversationId = currentConversation?.id else {
            createConversation()
            return
        }

        let userMessage = Message(
            conversationId: conversationId,
            role: .user,
            content: userInput,
            contextSnapshot: ContextSnapshot(
                messageId: UUID(),
                contextWindowUsed: attachedContext.count,
                tokensUsed: 0,
                modelVersion: selectedModel
            )
        )

        do {
            try storageService.saveMessage(userMessage)
            messages.append(userMessage)
            userInput = ""
            streamingText = ""

            await sendToAPI(messages: messages, conversationId: conversationId)
        } catch {
            errorMessage = "Failed to save message: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendToAPI(messages: [Message], conversationId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        let messageRequests = messages.map { message in
            MessageRequest(role: message.role.rawValue, content: message.content)
        }

        do {
            let response = try await apiClient.sendMessage(
                messages: messageRequests,
                model: selectedModel,
                maxTokens: 1024,
                temperature: temperature
            )

            guard let choice = response.choices.first,
                  let assistantContent = choice.message?.content else {
                throw NSError(domain: "ChatViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from API"])
            }

            let assistantMessage = Message(
                conversationId: conversationId,
                role: .assistant,
                content: assistantContent,
                contextSnapshot: ContextSnapshot(
                    messageId: UUID(),
                    contextWindowUsed: attachedContext.count,
                    tokensUsed: response.usage?.completion_tokens ?? 0,
                    modelVersion: selectedModel
                )
            )

            try storageService.saveMessage(assistantMessage)
            messages.append(assistantMessage)

            var updatedConversation = currentConversation
            updatedConversation?.updatedAt = Date()
            updatedConversation?.messageCount = messages.count

            if let updatedConversation = updatedConversation {
                try storageService.updateConversation(updatedConversation)
                currentConversation = updatedConversation
            }

            loadConversations()
            loadMessagesForConversation(conversationId)
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }

    // MARK: - Streaming with Retry

    func sendMessageWithStreaming() {
        guard !userInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let conversationId = currentConversation?.id else {
            createConversation()
            return
        }

        let userMessage = Message(
            conversationId: conversationId,
            role: .user,
            content: userInput,
            contextSnapshot: ContextSnapshot(
                messageId: UUID(),
                contextWindowUsed: attachedContext.count,
                tokensUsed: 0,
                modelVersion: selectedModel
            )
        )

        do {
            try storageService.saveMessage(userMessage)
            messages.append(userMessage)
            userInput = ""
            streamingText = ""

            await sendToAPIWithRetry(messages: messages, conversationId: conversationId)
        } catch {
            errorMessage = "Failed to save message: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendToAPIWithRetry(messages: [Message], conversationId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        let messageRequests = messages.map { message in
            MessageRequest(role: message.role.rawValue, content: message.content)
        }

        await withCheckedContinuation { continuation in
            var fullContent = ""

            apiClient.streamMessageWithRetry(
                messages: messageRequests,
                model: selectedModel,
                maxTokens: 1024,
                temperature: temperature,
                maxRetries: 3,
                onChunk: { [weak self] chunk in
                    fullContent.append(chunk)
                    Task { @MainActor in
                        self?.streamingText = fullContent
                    }
                },
                onComplete: { [weak self] result in
                    guard let self = self else { return }

                    switch result {
                    case .success:
                        Task { @MainActor in
                            do {
                                let assistantMessage = Message(
                                    conversationId: conversationId,
                                    role: .assistant,
                                    content: fullContent,
                                    contextSnapshot: ContextSnapshot(
                                        messageId: UUID(),
                                        contextWindowUsed: self.attachedContext.count,
                                        tokensUsed: 0,
                                        modelVersion: self.selectedModel
                                    )
                                )

                                try self.storageService.saveMessage(assistantMessage)
                                self.messages.append(assistantMessage)

                                var updatedConversation = self.currentConversation
                                updatedConversation?.updatedAt = Date()
                                updatedConversation?.messageCount = self.messages.count

                                if let updatedConversation = updatedConversation {
                                    try self.storageService.updateConversation(updatedConversation)
                                    self.currentConversation = updatedConversation
                                }

                                self.streamingText = ""
                                self.loadConversations()
                                self.loadMessagesForConversation(conversationId)
                                continuation.resume()
                            } catch {
                                self.errorMessage = "Failed to save message: \(error.localizedDescription)"
                                continuation.resume()
                            }
                        }
                    case .failure(let error):
                        Task { @MainActor in
                            self.errorMessage = "Failed to send message: \(error.localizedDescription)"
                            self.streamingText = ""
                            continuation.resume()
                        }
                    }
                }
            )
        }
    }

    // MARK: - Context Management

    func attachContext(_ paths: [String]) {
        attachedContext.append(contentsOf: paths)
    }

    func removeContext(_ path: String) {
        attachedContext.removeAll { $0 == path }
    }

    func clearContext() {
        attachedContext.removeAll()
    }

    // MARK: - Search

    func searchConversations(_ query: String) -> [Conversation] {
        if query.isEmpty {
            return conversations
        }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Settings

    func setAPIKey(_ key: String) throws {
        try apiClient.setAPIKey(key)
    }

    func updateModel(_ model: String) {
        selectedModel = model
    }

    func updateTemperature(_ value: Double) {
        temperature = value
    }

    // MARK: - Statistics

    func getTotalTokens() throws -> (input: Int, output: Int) {
        return try costTracker.totalTokens()
    }

    func getTotalCost() throws -> Double {
        return try costTracker.totalCost()
    }
}
