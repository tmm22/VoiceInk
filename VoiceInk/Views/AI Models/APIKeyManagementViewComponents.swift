import SwiftUI
import AppKit

struct APIProviderPickerRow: View {
    @Binding var selectedProvider: AIProvider
    let isAPIKeyValid: Bool
    let isCheckingOllama: Bool
    let hasOllamaModels: Bool

    var body: some View {
        HStack {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(AIProvider.allCases.filter { $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox }, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.automatic)
            .tint(.blue)

            Spacer()

            if selectedProvider == .ollama {
                if isCheckingOllama {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    APIConnectionBadge(
                        isConnected: hasOllamaModels,
                        title: hasOllamaModels ? "Connected" : "Disconnected"
                    )
                }
            } else if isAPIKeyValid {
                APIConnectionBadge(isConnected: true, title: "Connected")
            }
        }
    }
}

struct APIModelSelectionSection: View {
    @ObservedObject var aiService: AIService
    let refreshOpenRouterModels: () -> Void

    var body: some View {
        if aiService.selectedProvider == .openRouter {
            openRouterSelection
        } else if !aiService.availableModels.isEmpty &&
                    aiService.selectedProvider != .ollama &&
                    aiService.selectedProvider != .custom {
            Picker("Model", selection: Binding(
                get: { aiService.currentModel },
                set: { aiService.selectModel($0) }
            )) {
                ForEach(aiService.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }

    private var openRouterSelection: some View {
        Group {
            if aiService.availableModels.isEmpty {
                HStack {
                    Text("No models loaded")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: refreshOpenRouterModels) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            } else {
                HStack {
                    Picker("Model", selection: Binding(
                        get: { aiService.currentModel },
                        set: { aiService.selectModel($0) }
                    )) {
                        ForEach(aiService.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    Spacer()

                    Button(action: refreshOpenRouterModels) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

struct OllamaProviderSection: View {
    @ObservedObject var aiService: AIService
    @Binding var baseURL: String
    let models: [OllamaAIService.OllamaModel]
    @Binding var selectedModel: String
    let isChecking: Bool
    @Binding var isEditingURL: Bool
    let onSaveURL: () -> Void
    let onResetURL: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditingURL {
                HStack {
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)

                    Button("Save", action: onSaveURL)
                }
            } else {
                HStack {
                    Text("Server: \(baseURL)")
                    Spacer()
                    Button("Edit") { isEditingURL = true }
                    Button(action: onResetURL) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help("Reset to default")
                }
            }

            HStack {
                Label("Model", systemImage: "cpu")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if models.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("No models available")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                } else {
                    Picker("Ollama model", selection: $selectedModel) {
                        ForEach(models) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    .onChange(of: selectedModel) { _, newValue in
                        aiService.updateSelectedOllamaModel(newValue)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                }

                Button(action: onRefresh) {
                    Label(isChecking ? "Refreshing..." : "Refresh", systemImage: isChecking ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.caption)
                }
                .disabled(isChecking)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if models.isEmpty {
                APIKeyTroubleshootingCard()
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(12)
    }
}

struct CustomProviderSection: View {
    @ObservedObject var aiService: AIService
    @Binding var apiKey: String
    let isVerifying: Bool
    let onVerifyAndSave: () -> Void
    let onClearKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("API Endpoint URL", text: $aiService.customBaseURL)
                .textFieldStyle(.roundedBorder)

            Divider()

            TextField("Model Name", text: $aiService.customModel)
                .textFieldStyle(.roundedBorder)

            Divider()

            if aiService.isAPIKeyValid {
                HStack {
                    Text("API Key Set")
                    Spacer()
                    Button("Remove Key", role: .destructive, action: onClearKey)
                }
            } else {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Verify and Save", action: onVerifyAndSave)
                    .disabled(aiService.customBaseURL.isEmpty || aiService.customModel.isEmpty || apiKey.isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !aiService.isAPIKeyValid {
                    TextField("API Endpoint URL (e.g., https://api.example.com/v1/chat/completions)", text: $aiService.customBaseURL)
                        .textFieldStyle(.roundedBorder)

                    TextField("Model Name (e.g., gpt-4o-mini, claude-3-5-sonnet-20240620)", text: $aiService.customModel)
                        .textFieldStyle(.roundedBorder)
                } else {
                    APIKeyValueGroup(title: "API Endpoint URL", value: aiService.customBaseURL)
                    APIKeyValueGroup(title: "Model", value: aiService.customModel)
                }

                if aiService.isAPIKeyValid {
                    APIKeyMaskedValueRow(onClearKey: onClearKey)
                } else {
                    Text("Enter your API Key")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    HStack {
                        Button(action: onVerifyAndSave) {
                            HStack {
                                if isVerifying {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Text("Verify and Save")
                            }
                        }
                        .disabled(aiService.customBaseURL.isEmpty || aiService.customModel.isEmpty || apiKey.isEmpty)

                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(12)
    }
}

struct StandardProviderKeySection: View {
    @ObservedObject var aiService: AIService
    @Binding var apiKey: String
    let isVerifying: Bool
    let onVerifyAndSave: () -> Void
    let onClearKey: () -> Void

    var body: some View {
        Group {
            if aiService.isAPIKeyValid {
                APIKeyMaskedValueRow(onClearKey: onClearKey)
            } else {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if let url = aiService.selectedProvider.apiKeyURL {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "key.fill")
                                Text("Get API Key")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button(action: onVerifyAndSave) {
                        HStack {
                            if isVerifying {
                                ProgressView().controlSize(.small)
                            }
                            Text("Verify and Save")
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Text(aiService.selectedProvider.billingLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)

                        Button {
                            if let url = aiService.selectedProvider.apiKeyURL {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Get API Key")
                                    .foregroundColor(.accentColor)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(aiService.selectedProvider.apiKeyURL == nil)
                    }
                }
            }
        }
    }
}

private struct APIConnectionBadge: View {
    let isConnected: Bool
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

private struct APIKeyTroubleshootingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Troubleshooting")
                .font(.subheadline)
                .bold()

            VStack(alignment: .leading, spacing: 4) {
                bulletPoint("Ensure Ollama is installed and running")
                bulletPoint("Check if the server URL is correct")
                bulletPoint("Verify you have at least one model pulled")
            }

            Button("Learn More") {
                if let url = URL(string: "https://ollama.ai/download") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct APIKeyValueGroup: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private struct APIKeyMaskedValueRow: View {
    let onClearKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Text(String(repeating: "•", count: 40))
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Button(action: onClearKey) {
                    Label("Remove Key", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
