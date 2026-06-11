import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var errorMessage: String?
    @State private var isProcessing: Bool = false
    @State private var showAPIKeySection: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Welcome to ClaudeQuick")
                    .font(.title)

                Text("Choose how to authenticate")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Claude Pro option
            Button(action: connectClaudePro) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Claude Pro Subscription")
                            .font(.headline)
                        Text("Connect via your existing Claude Code login")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)

            // Divider
            HStack {
                Rectangle().frame(height: 1).foregroundColor(Color(.separatorColor))
                Text("or").font(.caption).foregroundColor(.secondary).padding(.horizontal, 8)
                Rectangle().frame(height: 1).foregroundColor(Color(.separatorColor))
            }

            // API Key option
            if showAPIKeySection {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill").foregroundColor(.accentColor)
                        Text("Anthropic API Key").font(.headline)
                    }

                    SecureField("sk-ant-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.monospaced(.body)())

                    HStack {
                        Button("Open Console") {
                            NSWorkspace.shared.open(URL(string: "https://console.anthropic.com")!)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(action: saveAPIKey) {
                            Text("Continue")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyInput.isEmpty || isProcessing)
                    }
                }
                .padding(16)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Button("Use API Key instead") {
                    showAPIKeySection = true
                }
                .foregroundColor(.secondary)
                .font(.callout)
            }

            if let errorMessage = errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Text("Credentials stored securely in macOS Keychain")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 520)
    }

    private func connectClaudePro() {
        errorMessage = nil
        isProcessing = true
        do {
            try appState.connectClaudePro()
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    private func saveAPIKey() {
        errorMessage = nil
        isProcessing = true
        do {
            try appState.setAPIKey(apiKeyInput)
        } catch {
            errorMessage = "Failed to save API key: \(error.localizedDescription)"
            isProcessing = false
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
