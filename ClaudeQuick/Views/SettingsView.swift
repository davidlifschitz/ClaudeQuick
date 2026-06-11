import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var apiKeyInput: String = ""
    @State private var showAPIKeyInput: Bool = false
    @State private var apiKeySaved: Bool = false
    @State private var temperatureValue: Double = 0.7
    @State private var selectedModel: String = "claude-3-5-sonnet-20241022"
    @State private var totalCost: Double = 0.0
    @State private var totalTokens: (input: Int, output: Int) = (0, 0)
    @State private var errorMessage: String?

    let models = [
        "claude-3-5-sonnet-20241022",
        "claude-3-opus-20250219",
        "claude-3-haiku-20250307"
    ]

    var body: some View {
        NavigationView {
            Form {
                // API Key Section
                Section("API Configuration") {
                    if showAPIKeyInput {
                        HStack {
                            SecureField("Enter API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)

                            Button(action: saveAPIKey) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .disabled(apiKeyInput.isEmpty)
                        }

                        if apiKeySaved {
                            Label("API Key saved", systemImage: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                    } else {
                        Button(action: { showAPIKeyInput = true }) {
                            HStack {
                                Image(systemName: "key.fill")
                                Text("Update API Key")
                            }
                        }
                    }
                }

                // Model Selection
                Section("Model Settings") {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models, id: \.self) { model in
                            Text(modelDisplayName(model))
                                .tag(model)
                        }
                    }
                    .onChange(of: selectedModel) { newValue in
                        chatViewModel.updateModel(newValue)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", temperatureValue))
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $temperatureValue, in: 0...2, step: 0.1)
                            .onChange(of: temperatureValue) { newValue in
                                chatViewModel.updateTemperature(newValue)
                            }

                        Text("Lower = more focused, Higher = more creative")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Usage Statistics
                Section("Usage Statistics") {
                    if totalTokens.input > 0 || totalTokens.output > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Total Cost")
                                Spacer()
                                Text(String(format: "$%.4f", totalCost))
                                    .font(.headline)
                            }

                            HStack {
                                Text("Input Tokens")
                                Spacer()
                                Text("\(totalTokens.input)")
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Output Tokens")
                                Spacer()
                                Text("\(totalTokens.output)")
                                    .foregroundColor(.secondary)
                            }

                            Button(role: .destructive) {
                                clearStatistics()
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Clear Statistics")
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        Text("No usage data yet")
                            .foregroundColor(.secondary)
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("API Endpoint")
                        Spacer()
                        Text("api.anthropic.com")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSettings()
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    // MARK: - Private Methods

    private func saveAPIKey() {
        do {
            try appState.setAPIKey(apiKeyInput)
            apiKeySaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                apiKeyInput = ""
                showAPIKeyInput = false
                apiKeySaved = false
            }
        } catch {
            errorMessage = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    private func loadSettings() {
        selectedModel = chatViewModel.selectedModel
        temperatureValue = chatViewModel.temperature

        do {
            totalCost = try chatViewModel.getTotalCost()
            totalTokens = try chatViewModel.getTotalTokens()
        } catch {
            errorMessage = "Failed to load statistics: \(error.localizedDescription)"
        }
    }

    private func clearStatistics() {
        do {
            try chatViewModel.costTracker.clearUsage()
            totalCost = 0.0
            totalTokens = (0, 0)
        } catch {
            errorMessage = "Failed to clear statistics: \(error.localizedDescription)"
        }
    }

    private func modelDisplayName(_ model: String) -> String {
        switch model {
        case "claude-3-5-sonnet-20241022":
            return "Sonnet 3.5 (Balanced)"
        case "claude-3-opus-20250219":
            return "Opus 3 (Most Capable)"
        case "claude-3-haiku-20250307":
            return "Haiku 3 (Fastest)"
        default:
            return model
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ChatViewModel())
        .environmentObject(AppState())
}
