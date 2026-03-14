import SwiftUI

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @State private var apiKey = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    @State private var ollamaBaseURL = AppSettings.Ollama.baseURL
    @State private var ollamaModels: [OllamaAIService.OllamaModel] = []
    @State private var selectedOllamaModel = AppSettings.Ollama.selectedModel
    @State private var isCheckingOllama = false
    @State private var isEditingURL = false

    var body: some View {
        Section("AI Provider Integration") {
            APIProviderPickerRow(
                selectedProvider: $aiService.selectedProvider,
                isAPIKeyValid: aiService.isAPIKeyValid,
                isCheckingOllama: isCheckingOllama,
                hasOllamaModels: !ollamaModels.isEmpty
            )
            .onChange(of: aiService.selectedProvider) { _, newValue in
                if newValue == .ollama {
                    checkOllamaConnection()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                APIModelSelectionSection(
                    aiService: aiService,
                    refreshOpenRouterModels: refreshOpenRouterModels
                )

                Divider()

                providerSection
            }
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            aiService.loadStoredAPIKeyForSelectedProvider()
            if aiService.selectedProvider == .ollama {
                checkOllamaConnection()
            }
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        switch aiService.selectedProvider {
        case .ollama:
            OllamaProviderSection(
                aiService: aiService,
                baseURL: $ollamaBaseURL,
                models: ollamaModels,
                selectedModel: $selectedOllamaModel,
                isChecking: isCheckingOllama,
                isEditingURL: $isEditingURL,
                onSaveURL: saveOllamaURL,
                onResetURL: resetOllamaURL,
                onRefresh: checkOllamaConnection
            )
        case .custom:
            CustomProviderSection(
                aiService: aiService,
                apiKey: $apiKey,
                isVerifying: isVerifying,
                onVerifyAndSave: verifyAndSaveAPIKey,
                onClearKey: { aiService.clearAPIKey() }
            )
        default:
            StandardProviderKeySection(
                aiService: aiService,
                apiKey: $apiKey,
                isVerifying: isVerifying,
                onVerifyAndSave: verifyAndSaveAPIKey,
                onClearKey: { aiService.clearAPIKey() }
            )
        }
    }

    private func refreshOpenRouterModels() {
        Task {
            await aiService.fetchOpenRouterModels()
        }
    }

    private func saveOllamaURL() {
        aiService.updateOllamaBaseURL(ollamaBaseURL)
        checkOllamaConnection()
        isEditingURL = false
    }

    private func resetOllamaURL() {
        ollamaBaseURL = AppSettings.Ollama.defaultBaseURL
        aiService.updateOllamaBaseURL(ollamaBaseURL)
        checkOllamaConnection()
    }

    private func verifyAndSaveAPIKey() {
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
}
