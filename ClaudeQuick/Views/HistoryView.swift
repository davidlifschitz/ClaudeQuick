import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @State private var searchText: String = ""
    @State private var selectedConversation: Conversation?

    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return chatViewModel.conversations.sorted { $0.updatedAt > $1.updatedAt }
        }
        return chatViewModel.searchConversations(searchText).sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)

                Button(action: {
                    chatViewModel.createConversation()
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Conversation")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Divider()

            // Conversation List
            if filteredConversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("No conversations")
                        .font(.headline)

                    Text(searchText.isEmpty ? "Create a new conversation to get started" : "No matching conversations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)

                Spacer()
            } else {
                List(filteredConversations, id: \.id, selection: $selectedConversation) { conversation in
                    ConversationRow(conversation: conversation)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            chatViewModel.selectConversation(conversation)
                            selectedConversation = conversation
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                chatViewModel.deleteConversation(conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Conversations")
        .frame(minWidth: 250)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.body)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 12) {
                Text("\(conversation.messageCount) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HistoryView()
        .environmentObject(ChatViewModel())
}
