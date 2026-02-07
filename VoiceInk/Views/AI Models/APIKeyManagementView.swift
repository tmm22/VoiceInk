import SwiftUI

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @State private var apiKey: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    @State private var ollamaBaseURL: String = AppSettings.Ollama.baseURL
    @State private var ollamaModels: [OllamaAIService.OllamaModel] = []
    @State private var selectedOllamaModel: String = AppSettings.Ollama.selectedModel
    @State private var isCheckingOllama = false
    @State private var isEditingURL = false
    
    var body: some View {
        Section("AI Provider Integration") {
            HStack {
                Picker("Provider", selection: $aiService.selectedProvider) {
                    ForEach(AIProvider.allCases.filter { $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox }, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.automatic)
                .tint(.blue)
                
                // Show connected status for all providers
                if aiService.isAPIKeyValid && aiService.selectedProvider != .ollama {
                    Spacer()
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if aiService.selectedProvider == .ollama {
                    Spacer()
                    if isCheckingOllama {
                        ProgressView()
                            .controlSize(.small)
                    } else if !ollamaModels.isEmpty {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Disconnected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: aiService.selectedProvider) { oldValue, newValue in
                if aiService.selectedProvider == .ollama {
                    checkOllamaConnection()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Model Selection
                if aiService.selectedProvider == .openRouter {
                    if aiService.availableModels.isEmpty {
                        HStack {
                            Text("No models loaded")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                Task {
                                    await aiService.fetchOpenRouterModels()
                                }
                            }) {
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

                            Button(action: {
                                Task {
                                    await aiService.fetchOpenRouterModels()
                                }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    
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

                Divider()

                if aiService.selectedProvider == .ollama {
                    // Ollama Configuration inline
                    if isEditingURL {
                        HStack {
                            TextField("Base URL", text: $ollamaBaseURL)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Save") {
                                aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                                isEditingURL = false
                            }
                        }
                    } else {
                        HStack {
                            Text("Server: \(ollamaBaseURL)")
                            Spacer()
                            Button("Edit") { isEditingURL = true }
                            Button(action: {
                                ollamaBaseURL = AppSettings.Ollama.defaultBaseURL
                                aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .help("Reset to default")
                        }
                    }
                    
                    // Model selection and refresh
                    HStack {
                        Label("Model", systemImage: "cpu")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if ollamaModels.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("No models available")
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        } else {
                            Picker("", selection: $selectedOllamaModel) {
                                ForEach(ollamaModels) { model in
                                    Text(model.name).tag(model.name)
                                }
                            }
                            .onChange(of: selectedOllamaModel) { oldValue, newValue in
                                aiService.updateSelectedOllamaModel(newValue)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 150)
                        }
                        
                        Button(action: { checkOllamaConnection() }) {
                            Label(isCheckingOllama ? "Refreshing..." : "Refresh", systemImage: isCheckingOllama ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .font(.caption)
                        }
                        .disabled(isCheckingOllama)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    // Help text for troubleshooting
                    if ollamaModels.isEmpty {
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
                }
                .padding()
                .background(Color.secondary.opacity(0.03))
                .cornerRadius(12)

                    if !ollamaModels.isEmpty {
                        Divider()

                        Picker("Model", selection: $selectedOllamaModel) {
                            ForEach(ollamaModels) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .onChange(of: selectedOllamaModel) { oldValue, newValue in
                            aiService.updateSelectedOllamaModel(newValue)
                        }
                    }

                } else if aiService.selectedProvider == .custom {
                    // Custom Configuration inline
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
                            Button("Remove Key", role: .destructive) {
                                aiService.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        Button("Verify and Save") {
                            isVerifying = true
                            aiService.saveAPIKey(apiKey) { success, errorMessage in
                                isVerifying = false
                                if !success {
                                    alertMessage = errorMessage ?? "Verification failed"
                                    showAlert = true
                                }
                                apiKey = ""
                            }
                        }
                        .disabled(aiService.customBaseURL.isEmpty || aiService.customModel.isEmpty || apiKey.isEmpty)
                    }
                    
                    // Configuration Fields
                    VStack(alignment: .leading, spacing: 8) {
                        if !aiService.isAPIKeyValid {
                            TextField("API Endpoint URL (e.g., https://api.example.com/v1/chat/completions)", text: $aiService.customBaseURL)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("Model Name (e.g., gpt-4o-mini, claude-3-5-sonnet-20240620)", text: $aiService.customModel)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("API Endpoint URL")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(aiService.customBaseURL)
                                    .font(.system(.body, design: .monospaced))
                                
                                Text("Model")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(aiService.customModel)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        
                        if aiService.isAPIKeyValid {
                            Text("API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(String(repeating: "•", count: 40))
                                    .font(.system(.body, design: .monospaced))
                                
                                Spacer()
                                
                                Button(action: {
                                    aiService.clearAPIKey()
                                }) {
                                    Label("Remove Key", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Text("Enter your API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            HStack {
                                Button(action: {
                                    isVerifying = true
                                    aiService.saveAPIKey(apiKey) { success, errorMessage in
                                        isVerifying = false
                                        if !success {
                                            alertMessage = errorMessage ?? "Verification failed"
                                            showAlert = true
                                        }
                                        apiKey = ""
                                    }
                                }) {
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
            } else {
                // API Key Display for other providers if valid
                if aiService.isAPIKeyValid {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(String(repeating: "•", count: 40))
                                .font(.system(.body, design: .monospaced))
                            
                            Spacer()
                            
                            Button(action: {
                                aiService.clearAPIKey()
                            }) {
                                Label("Remove Key", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else {
                    // API Key Display for other providers
                    if aiService.isAPIKeyValid {
                        HStack {
                            Text("API Key")
                            Spacer()
                            Text("••••••••")
                                .foregroundColor(.secondary)
                            Button("Remove", role: .destructive) {
                                aiService.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            // Get API Key Link
                            if let url = getAPIKeyURL() {
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

                            Button(action: {
                                isVerifying = true
                                aiService.saveAPIKey(apiKey) { success, errorMessage in
                                    isVerifying = false
                                    if !success {
                                        alertMessage = errorMessage ?? "Verification failed"
                                        showAlert = true
                                    }
                                    apiKey = ""
                                }
                            }) {
                                HStack {
                                    if isVerifying {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text("Verify and Save")
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Text((aiService.selectedProvider == .groq || aiService.selectedProvider == .gemini || aiService.selectedProvider == .cerebras || aiService.selectedProvider == .zai) ? "Free" : "Paid")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                
                                if aiService.selectedProvider != .ollama && aiService.selectedProvider != .custom {
                                    Button {
                                        let urlString: String? = switch aiService.selectedProvider {
                                        case .groq:
                                            "https://console.groq.com/keys"
                                        case .openAI:
                                            "https://platform.openai.com/api-keys"
                                        case .gemini:
                                            "https://makersuite.google.com/app/apikey"
                                        case .anthropic:
                                            "https://console.anthropic.com/settings/keys"
                                        case .mistral:
                                            "https://console.mistral.ai/api-keys"
                                        case .elevenLabs:
                                            "https://elevenlabs.io/speech-synthesis"
                                        case .deepgram:
                                            "https://console.deepgram.com/api-keys"
                                        case .soniox:
                                            "https://console.soniox.com/"
                                        case .assemblyAI:
                                            "https://www.assemblyai.com/app/api-keys"
                                        case .openRouter:
                                            "https://openrouter.ai/keys"
                                        case .cerebras:
                                            "https://cloud.cerebras.ai/"
                                        case .zai:
                                            "https://z.ai/manage-apikey/apikey-list"
                                        case .ollama, .custom:
                                            nil // This case should never be reached
                                        }
                                        if let urlString, let url = URL(string: urlString) {
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
                                }
                            }
                        }
                    }
                }
            }
            
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if aiService.selectedProvider == .ollama {
                checkOllamaConnection()
            }
        }
    }
    
    private func checkOllamaConnection() {
        isCheckingOllama = true
        aiService.checkOllamaConnection { connected in
            if connected {
                Task {
                    ollamaModels = await aiService.fetchOllamaModels()
                    isCheckingOllama = false
                }
            } else {
                ollamaModels = []
                isCheckingOllama = false
                alertMessage = "Could not connect to Ollama. Please check if Ollama is running and the base URL is correct."
                showAlert = true
            }
        }
    }
    
    private func getAPIKeyURL() -> URL? {
        switch aiService.selectedProvider {
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://makersuite.google.com/app/apikey")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .elevenLabs: return URL(string: "https://elevenlabs.io/speech-synthesis")
        case .deepgram: return URL(string: "https://console.deepgram.com/api-keys")
        case .soniox: return URL(string: "https://console.soniox.com/")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .cerebras: return URL(string: "https://cloud.cerebras.ai/")
        default: return nil
        }
    }
}
