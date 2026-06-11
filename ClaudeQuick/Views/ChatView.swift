import SwiftUI

enum SidebarTab {
    case chat, insights
}

struct ChatView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var appState: AppState
    @State private var showHistoryPanel = true
    @State private var sidebarTab: SidebarTab = .chat

    var body: some View {
        NavigationView {
            // Sidebar - Tab Navigation
            VStack(spacing: 0) {
                Picker("", selection: $sidebarTab) {
                    Image(systemName: "bubble.left.and.bubble.right").tag(SidebarTab.chat)
                    Image(systemName: "chart.bar").tag(SidebarTab.insights)
                }
                .pickerStyle(.segmented)
                .padding(8)

                if sidebarTab == .chat {
                    HistoryView()
                        .environmentObject(chatViewModel)
                } else {
                    InsightsView()
                }
            }
            .frame(minWidth: 260)

            // Main Chat Area
            if let conversation = chatViewModel.currentConversation {
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(conversation.title)
                                .font(.headline)
                                .lineLimit(1)

                            Spacer()

                            Button(action: { appState.showSettingsSheet = true }) {
                                Image(systemName: "gear")
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .help("Settings")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.controlBackgroundColor))
                    .borderBottom()

                    // Messages Area
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(chatViewModel.messages) { message in
                                    MessageRow(message: message)
                                        .id(message.id)
                                }

                                if !chatViewModel.streamingText.isEmpty {
                                    MessageRow(message: Message(
                                        conversationId: conversation.id,
                                        role: .assistant,
                                        content: chatViewModel.streamingText
                                    ))
                                }

                                if chatViewModel.isLoading && chatViewModel.streamingText.isEmpty {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Thinking...")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                }

                                if let error = chatViewModel.errorMessage {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.red)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                        Spacer()
                                        Button("Dismiss") { chatViewModel.errorMessage = nil }
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.08))
                                }

                                Spacer()
                                    .frame(height: 1)
                                    .id("bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: chatViewModel.messages.count) { _ in
                            scrollProxy.scrollTo("bottom", anchor: .bottom)
                        }
                        .onChange(of: chatViewModel.streamingText) { _ in
                            scrollProxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }

                    Divider()

                    // Context Badge
                    if !chatViewModel.attachedContext.isEmpty {
                        ContextBadge()
                            .environmentObject(chatViewModel)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }

                    // Input Area
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Type a message...", text: $chatViewModel.userInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)

                            Button(action: {
                                chatViewModel.sendMessage()
                            }) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(chatViewModel.userInput.trimmingCharacters(in: .whitespaces).isEmpty || chatViewModel.isLoading)
                            .help("Send message (⌘+Enter)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.controlBackgroundColor))
                    .borderTop()
                }
            } else {
                VStack(spacing: 16) {
                    Text("No Conversation Selected")
                        .font(.headline)
                    Text("Create a new conversation or select one from the sidebar")
                        .foregroundColor(.secondary)

                    Button("New Conversation") {
                        chatViewModel.createConversation()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $appState.showSettingsSheet) {
            SettingsView()
                .environmentObject(chatViewModel)
                .environmentObject(appState)
        }
        .onAppear {
            if chatViewModel.currentConversation == nil && !chatViewModel.conversations.isEmpty {
                chatViewModel.selectConversation(chatViewModel.conversations[0])
            }
        }
    }
}

// MARK: - Helper Views

extension View {
    func borderTop() -> some View {
        self.border(Color(.separatorColor), width: 1)
    }

    func borderBottom() -> some View {
        self.border(Color(.separatorColor), width: 1)
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatViewModel())
        .environmentObject(AppState())
}
