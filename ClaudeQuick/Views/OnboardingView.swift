import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var errorMessage: String?
    @State private var isProcessing: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Welcome to ClaudeQuick")
                    .font(.title)
                    .font(.title)

                Text("Get started by adding your Anthropic API key")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("1")
                            .font(.headline)
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get your API key")
                                .font(.headline)
                            Text("Visit console.anthropic.com")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button("Open Anthropic Console") {
                        if let url = URL(string: "https://console.anthropic.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                HStack(spacing: 8) {
                    Text("2")
                        .font(.headline)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paste your API key below")
                            .font(.headline)
                        Text("Your key is stored securely in Keychain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Label("API Key", systemImage: "key.fill")
                    .font(.headline)

                SecureField("sk-ant-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.monospaced(.body)())
                    .disabled(isProcessing)

                if let errorMessage = errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            // Action Buttons
            VStack(spacing: 8) {
                Button(action: saveAPIKey) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.isEmpty || isProcessing)
                .frame(maxWidth: .infinity)
                .frame(height: 44)

                Text("Your API key is never stored locally. It's saved securely in your macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 600)
    }

    // MARK: - Private Methods

    private func saveAPIKey() {
        errorMessage = nil
        isProcessing = true

        do {
            try appState.setAPIKey(apiKeyInput)
            // The view will automatically update due to @Published change
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
