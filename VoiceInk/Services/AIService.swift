import Foundation
import os

enum AIProvider: String, CaseIterable, Identifiable {
    case builtIn = "Built-in"
    case ollama = "Ollama"

    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .builtIn:
            return "voiceink-enhancer"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        }
    }
}

class AIService: ObservableObject {
    private let logger = Logger(subsystem: "voiceink.community", category: "AIService")

    @Published var selectedProvider: AIProvider {
        didSet {
            userDefaults.set(selectedProvider.rawValue, forKey: "selectedAIProvider")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)

            if selectedProvider == .ollama {
                Task {
                    await ensureOllamaReady()
                }
            }
        }
    }

    @Published private var selectedModels: [AIProvider: String] = [:]
    private let userDefaults = UserDefaults.standard
    @Published private(set) var builtInModelName: String = "voiceink-enhancer"
    private lazy var ollamaService = OllamaService()

    var availableProviders: [AIProvider] {
        var providers: [AIProvider] = [.builtIn]
        if ollamaService.isConnected {
            providers.append(.ollama)
        }
        return providers
    }

    var connectedProviders: [AIProvider] {
        availableProviders
    }

    var currentModel: String {
        if let selected = selectedModels[selectedProvider], !selected.isEmpty {
            return selected
        }

        switch selectedProvider {
        case .builtIn:
            return builtInModelName
        case .ollama:
            return ollamaService.selectedModel
        }
    }

    var availableModels: [String] {
        switch selectedProvider {
        case .builtIn:
            return [builtInModelName]
        case .ollama:
            return ollamaService.availableModels.map { $0.name }
        }
    }

    var isReady: Bool {
        switch selectedProvider {
        case .builtIn:
            return true
        case .ollama:
            return ollamaService.isConnected
        }
    }

    init() {
        if let savedProvider = userDefaults.string(forKey: "selectedAIProvider"),
           let provider = AIProvider(rawValue: savedProvider) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .builtIn
        }

        loadSavedModelSelections()

        if selectedProvider == .ollama {
            Task {
                await ensureOllamaReady()
            }
        }
    }

    func selectModel(_ model: String) {
        guard !model.isEmpty else { return }
        selectedModels[selectedProvider] = model
        userDefaults.set(model, forKey: "\(selectedProvider.rawValue)SelectedModel")

        if selectedProvider == .ollama {
            updateSelectedOllamaModel(model)
        }

        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    func refreshOllamaModels() async {
        await ensureOllamaReady()
    }

    func enhanceWithOllama(text: String, systemPrompt: String?) async throws -> String {
        guard selectedProvider == .ollama else {
            throw LocalAIError.serviceUnavailable
        }

        try await ensureOllamaReady()
        return try await ollamaService.enhance(text, withSystemPrompt: systemPrompt)
    }

    private func ensureOllamaReady() async {
        await ollamaService.checkConnection()
        await ollamaService.refreshModels()
    }

    private func loadSavedModelSelections() {
        for provider in AIProvider.allCases {
            let key = "\(provider.rawValue)SelectedModel"
            if let savedModel = userDefaults.string(forKey: key), !savedModel.isEmpty {
                selectedModels[provider] = savedModel
            }
        }
    }

    private func updateSelectedOllamaModel(_ model: String) {
        userDefaults.set(model, forKey: "ollamaSelectedModel")
    }
}
