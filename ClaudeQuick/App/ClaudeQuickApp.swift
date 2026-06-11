import SwiftUI

@main
struct ClaudeQuickApp: App {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.isAPIKeySet {
                ChatView()
                    .environmentObject(chatViewModel)
                    .environmentObject(appState)
            } else {
                OnboardingView()
                    .environmentObject(appState)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizabilityContentSize()
    }
}
