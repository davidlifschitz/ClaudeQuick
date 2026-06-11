import SwiftUI
import AppKit

// MARK: - KeyAwareTextField (macOS 12+ compatible key handling)

/// A text field that intercepts specific key presses before they reach AppKit's default handling,
/// enabling Escape/arrow/Return navigation for popovers without requiring macOS 14.
struct KeyAwareTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    /// Called on every key-down. Return true to suppress the event (consume it).
    var onKeyDown: ((UInt16, NSEvent.ModifierFlags) -> Bool)?
    /// Called when Cmd+Return is pressed.
    var onCmdReturn: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> InterceptingTextField {
        let field = InterceptingTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.onKeyDown = onKeyDown
        field.onCmdReturn = onCmdReturn
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.isEditable = true
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: InterceptingTextField, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onCmdReturn = onCmdReturn
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: KeyAwareTextField
        init(_ parent: KeyAwareTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
    }
}

class InterceptingTextField: NSTextField {
    var onKeyDown: ((UInt16, NSEvent.ModifierFlags) -> Bool)?
    var onCmdReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Cmd+Return → send
        if event.modifierFlags.contains(.command) && (event.keyCode == 36 || event.keyCode == 76) {
            onCmdReturn?()
            return
        }
        // Forward to popover handler; consume if handled
        if let consumed = onKeyDown?(event.keyCode, event.modifierFlags), consumed {
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Command Palette Item

struct CommandItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let action: String
}

// MARK: - SidebarTab (kept from original)

enum SidebarTab {
    case chat, insights
}

// MARK: - ChatView

struct ChatView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var appState: AppState
    @State private var showHistoryPanel = true
    @State private var sidebarTab: SidebarTab = .chat

    // Command palette ($)
    @State private var showCommandPalette = false
    @State private var commandFilter = ""
    @State private var commandSelection = 0

    // Context picker (@)
    @State private var showContextPicker = false
    @State private var contextFilter = ""
    @State private var contextSelection = 0

    // Sub-sheets
    @State private var showModelPicker = false
    @State private var showSystemPromptSheet = false
    @State private var systemPromptText = ""

    let allCommands: [CommandItem] = [
        CommandItem(title: "/clear",  subtitle: "Clear conversation",  action: "clear"),
        CommandItem(title: "/new",    subtitle: "New conversation",    action: "new"),
        CommandItem(title: "/model",  subtitle: "Pick model",          action: "model"),
        CommandItem(title: "/system", subtitle: "Set system prompt",   action: "system"),
    ]

    let availableModels = [
        "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001",
        "claude-opus-4-8",
    ]

    var filteredCommands: [CommandItem] {
        if commandFilter.isEmpty { return allCommands }
        return allCommands.filter {
            $0.title.localizedCaseInsensitiveContains(commandFilter) ||
            $0.subtitle.localizedCaseInsensitiveContains(commandFilter)
        }
    }

    var filteredContextItems: [String] {
        let files = chatViewModel.attachedContext
        if contextFilter.isEmpty { return files }
        return files.filter { $0.localizedCaseInsensitiveContains(contextFilter) }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            // Sidebar — Tab Navigation
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

                                // Live streaming bubble
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

                    // Input Area + popovers
                    inputAreaWithPopovers
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
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(
                models: availableModels,
                currentModel: chatViewModel.selectedModel
            ) { model in
                chatViewModel.updateModel(model)
                showModelPicker = false
            }
        }
        .sheet(isPresented: $showSystemPromptSheet) {
            SystemPromptSheet(text: $systemPromptText)
        }
        .onAppear {
            if chatViewModel.currentConversation == nil && !chatViewModel.conversations.isEmpty {
                chatViewModel.selectConversation(chatViewModel.conversations[0])
            }
        }
    }

    // MARK: - Input area with popovers

    @ViewBuilder
    private var inputAreaWithPopovers: some View {
        ZStack(alignment: .bottomLeading) {
            // Command palette floats above input bar
            if showCommandPalette && !filteredCommands.isEmpty {
                commandPaletteOverlay
                    .padding(.bottom, 52)
            }

            // Context picker floats above input bar
            if showContextPicker {
                contextPickerOverlay
                    .padding(.bottom, 52)
            }

            inputBar
        }
        .background(Color(.controlBackgroundColor))
        .borderTop()
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            KeyAwareTextField(
                placeholder: "Type a message… ($ commands, @ files)",
                text: $chatViewModel.userInput,
                onKeyDown: { keyCode, modifiers in
                    handlePopoverKeyDown(keyCode: keyCode, modifiers: modifiers)
                },
                onCmdReturn: {
                    doSend()
                }
            )
            .onChange(of: chatViewModel.userInput) { newValue in
                handleInputChange(newValue)
            }

            Button(action: doSend) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(chatViewModel.userInput.trimmingCharacters(in: .whitespaces).isEmpty || chatViewModel.isLoading)
            .help("Send message (⌘↩)")
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Returns true if the key was consumed by an open popover.
    @discardableResult
    private func handlePopoverKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        // Escape
        if keyCode == 53 {
            if showCommandPalette { dismissCommandPalette(stripTrigger: true); return true }
            if showContextPicker  { dismissContextPicker(stripTrigger: true);  return true }
        }
        // Up arrow
        if keyCode == 126 {
            if showCommandPalette { commandSelection = max(0, commandSelection - 1); return true }
            if showContextPicker  { contextSelection = max(0, contextSelection - 1); return true }
        }
        // Down arrow
        if keyCode == 125 {
            if showCommandPalette { commandSelection = min(filteredCommands.count - 1, commandSelection + 1); return true }
            if showContextPicker  { contextSelection = min(filteredContextItems.count, contextSelection + 1); return true }
        }
        // Return / Enter
        if keyCode == 36 || keyCode == 76 {
            if showCommandPalette { executeCommandSelection(); return true }
            if showContextPicker  { executeContextSelection();  return true }
        }
        return false
    }

    // MARK: - Command palette overlay

    private var commandPaletteOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredCommands.enumerated()), id: \.offset) { index, item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(index == commandSelection
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    commandSelection = index
                    executeCommandSelection()
                }
            }
        }
        .background(Color(.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -3)
        .padding(.horizontal, 16)
    }

    // MARK: - Context picker overlay

    private var contextPickerOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            if filteredContextItems.isEmpty {
                Text("No attached files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(filteredContextItems.enumerated()), id: \.offset) { index, path in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.body)
                            .lineLimit(1)
                        Text(path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(index == contextSelection
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        contextSelection = index
                        executeContextSelection()
                    }
                }
            }

            Divider()

            // "Attach file..." row — always shown
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("Attach file...")
                    .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(contextSelection == filteredContextItems.count
                ? Color.accentColor.opacity(0.18)
                : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissContextPicker(stripTrigger: true)
                openFilePicker()
            }
        }
        .background(Color(.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -3)
        .padding(.horizontal, 16)
    }

    // MARK: - Input change handler

    private func handleInputChange(_ newValue: String) {
        // Open command palette when $ is typed (not already open)
        if !showCommandPalette && !showContextPicker && newValue.hasSuffix("$") {
            commandFilter = ""
            commandSelection = 0
            showCommandPalette = true
            return
        }

        // Open context picker when @ is typed (not already open)
        if !showContextPicker && !showCommandPalette && newValue.hasSuffix("@") {
            contextFilter = ""
            contextSelection = 0
            showContextPicker = true
            return
        }

        // Update command filter live
        if showCommandPalette {
            if let idx = newValue.lastIndex(of: "$") {
                commandFilter = String(newValue[newValue.index(after: idx)...])
                commandSelection = 0
            } else {
                // $ removed — close without stripping further
                showCommandPalette = false
                commandFilter = ""
            }
        }

        // Update context filter live
        if showContextPicker {
            if let idx = newValue.lastIndex(of: "@") {
                contextFilter = String(newValue[newValue.index(after: idx)...])
                contextSelection = 0
            } else {
                showContextPicker = false
                contextFilter = ""
            }
        }
    }

    // MARK: - Command execution

    private func executeCommandSelection() {
        guard commandSelection < filteredCommands.count else {
            dismissCommandPalette(stripTrigger: true)
            return
        }
        let item = filteredCommands[commandSelection]
        dismissCommandPalette(stripTrigger: true)

        switch item.action {
        case "clear":
            chatViewModel.messages.removeAll()
        case "new":
            chatViewModel.createConversation()
        case "model":
            showModelPicker = true
        case "system":
            showSystemPromptSheet = true
        default:
            break
        }
    }

    private func dismissCommandPalette(stripTrigger: Bool) {
        showCommandPalette = false
        commandFilter = ""
        if stripTrigger, let idx = chatViewModel.userInput.lastIndex(of: "$") {
            chatViewModel.userInput = String(chatViewModel.userInput[..<idx])
        }
    }

    // MARK: - Context execution

    private func executeContextSelection() {
        let items = filteredContextItems
        if contextSelection == items.count {
            // "Attach file..." row selected
            dismissContextPicker(stripTrigger: true)
            openFilePicker()
            return
        }
        guard contextSelection < items.count else {
            dismissContextPicker(stripTrigger: true)
            return
        }

        let path = items[contextSelection]
        let filename = URL(fileURLWithPath: path).lastPathComponent

        // Replace @<filter> with @filename + space
        if let idx = chatViewModel.userInput.lastIndex(of: "@") {
            let before = String(chatViewModel.userInput[..<idx])
            chatViewModel.userInput = before + "@\(filename) "
        }
        showContextPicker = false
        contextFilter = ""
    }

    private func dismissContextPicker(stripTrigger: Bool) {
        showContextPicker = false
        contextFilter = ""
        if stripTrigger, let idx = chatViewModel.userInput.lastIndex(of: "@") {
            chatViewModel.userInput = String(chatViewModel.userInput[..<idx])
        }
    }

    // MARK: - File picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Attach Context Files"
        panel.prompt = "Attach"
        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path }
            chatViewModel.attachContext(paths)
        }
    }

    // MARK: - Send

    private func doSend() {
        guard !chatViewModel.userInput.trimmingCharacters(in: .whitespaces).isEmpty,
              !chatViewModel.isLoading else { return }
        chatViewModel.sendMessageWithStreaming()
    }
}

// MARK: - System Prompt Sheet

struct SystemPromptSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set System Prompt")
                .font(.headline)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Apply") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 220)
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    let models: [String]
    let currentModel: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Model")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(models, id: \.self) { model in
                HStack {
                    Text(model)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    if model == currentModel {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(model == currentModel
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(model) }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}

// MARK: - View extensions

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
