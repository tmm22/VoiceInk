import Foundation
import AppKit

struct ApplicationState: Codable {
    var isEnhancementEnabled: Bool
    var useScreenCaptureContext: Bool
    var selectedPromptId: String?
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var selectedLanguage: String?
    var transcriptionModelName: String?
}

struct PowerModeSession: Codable {
    let id: UUID
    let startTime: Date
    var originalState: ApplicationState
}

@MainActor
class PowerModeSessionManager {
    static let shared = PowerModeSessionManager()
    private var isApplyingPowerModeConfig = false

    private var whisperState: WhisperState?
    private var enhancementService: AIEnhancementService?

    private init() {
        recoverSession()
    }

    func configure(whisperState: WhisperState, enhancementService: AIEnhancementService) {
        self.whisperState = whisperState
        self.enhancementService = enhancementService
    }

    func beginSession(with config: PowerModeConfig) async {
        guard let whisperState = whisperState, let enhancementService = enhancementService else {
            #if DEBUG
            print("SessionManager not configured.")
            #endif
            return
        }

        let originalState = ApplicationState(
            isEnhancementEnabled: enhancementService.isEnhancementEnabled,
            useScreenCaptureContext: enhancementService.useScreenCaptureContext,
            selectedPromptId: enhancementService.selectedPromptId?.uuidString,
            selectedAIProvider: enhancementService.getAIService()?.selectedProvider.rawValue,
            selectedAIModel: enhancementService.getAIService()?.currentModel,
            selectedLanguage: AppSettings.TranscriptionSettings.selectedLanguage,
            transcriptionModelName: whisperState.currentTranscriptionModel?.name
        )

        let newSession = PowerModeSession(
            id: UUID(),
            startTime: Date(),
            originalState: originalState
        )
        saveSession(newSession)
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)

        isApplyingPowerModeConfig = true
        await applyConfiguration(config)
        isApplyingPowerModeConfig = false
    }

    func endSession() async {
        guard let session = loadSession() else { return }

        isApplyingPowerModeConfig = true
        await restoreState(session.originalState)
        isApplyingPowerModeConfig = false
        
        NotificationCenter.default.removeObserver(self, name: .AppSettingsDidChange, object: nil)

        clearSession()
    }
    
    @objc func updateSessionSnapshot() {
        guard !isApplyingPowerModeConfig else { return }
        
        guard var session = loadSession(), let whisperState = whisperState, let enhancementService = enhancementService else { return }

        let updatedState = ApplicationState(
            isEnhancementEnabled: enhancementService.isEnhancementEnabled,
            useScreenCaptureContext: enhancementService.useScreenCaptureContext,
            selectedPromptId: enhancementService.selectedPromptId?.uuidString,
            selectedAIProvider: enhancementService.getAIService()?.selectedProvider.rawValue,
            selectedAIModel: enhancementService.getAIService()?.currentModel,
            selectedLanguage: AppSettings.TranscriptionSettings.selectedLanguage,
            transcriptionModelName: whisperState.currentTranscriptionModel?.name
        )
        
        session.originalState = updatedState
        saveSession(session)
    }

    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard let enhancementService = enhancementService else { return }

        // No need for MainActor.run - this class is already @MainActor
        enhancementService.isEnhancementEnabled = config.isAIEnhancementEnabled
        enhancementService.useScreenCaptureContext = config.useScreenCapture

        if config.isAIEnhancementEnabled {
            if let promptId = config.selectedPrompt, let uuid = UUID(uuidString: promptId) {
                enhancementService.selectedPromptId = uuid
            }

            if let aiService = enhancementService.getAIService() {
                if let providerName = config.selectedAIProvider, let provider = AIProvider(rawValue: providerName) {
                    aiService.selectedProvider = provider
                }
                if let model = config.selectedAIModel {
                    aiService.selectModel(model)
                }
            }
        }

        if let language = config.selectedLanguage {
            AppSettings.TranscriptionSettings.selectedLanguage = language
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }

        if let whisperState = whisperState,
           let modelName = config.selectedTranscriptionModelName,
           let selectedModel = whisperState.allAvailableModels.first(where: { $0.name == modelName }),
           whisperState.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }
        
        NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
    }

    private func restoreState(_ state: ApplicationState) async {
        guard let enhancementService = enhancementService else { return }

        // No need for MainActor.run - this class is already @MainActor
        enhancementService.isEnhancementEnabled = state.isEnhancementEnabled
        enhancementService.useScreenCaptureContext = state.useScreenCaptureContext
        enhancementService.selectedPromptId = state.selectedPromptId.flatMap(UUID.init)

        if let aiService = enhancementService.getAIService() {
            if let providerName = state.selectedAIProvider, let provider = AIProvider(rawValue: providerName) {
                aiService.selectedProvider = provider
            }
            if let model = state.selectedAIModel {
                aiService.selectModel(model)
            }
        }

        if let language = state.selectedLanguage {
            AppSettings.TranscriptionSettings.selectedLanguage = language
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }

        if let whisperState = whisperState,
           let modelName = state.transcriptionModelName,
           let selectedModel = whisperState.allAvailableModels.first(where: { $0.name == modelName }),
           whisperState.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }
    }
    
    private func handleModelChange(to newModel: any TranscriptionModel) async {
        guard let whisperState = whisperState else { return }

        whisperState.setDefaultTranscriptionModel(newModel)

        switch newModel.provider {
        case .local:
            await whisperState.cleanupModelResources()
            if let localModel = whisperState.availableModels.first(where: { $0.name == newModel.name }) {
                do {
                    try await whisperState.loadModel(localModel)
                } catch {
                    #if DEBUG
                    print("Power Mode: Failed to load local model '\(localModel.name)': \(error)")
                    #endif
                }
            }
        case .parakeet:
            await whisperState.cleanupModelResources()

        default:
            await whisperState.cleanupModelResources()
        }
    }
    
    private func recoverSession() {
        guard let _ = loadSession() else { return }
        #if DEBUG
        print("Recovering abandoned Power Mode session.")
        #endif
        Task { [weak self] in
            await self?.endSession()
        }
    }

    private func saveSession(_ session: PowerModeSession) {
        do {
            let data = try JSONEncoder().encode(session)
            AppSettings.PowerMode.activeSessionData = data
        } catch {
            #if DEBUG
            print("Error saving Power Mode session: \(error)")
            #endif
        }
    }
    
    private func loadSession() -> PowerModeSession? {
        guard let data = AppSettings.PowerMode.activeSessionData else { return nil }
        do {
            return try JSONDecoder().decode(PowerModeSession.self, from: data)
        } catch {
            #if DEBUG
            print("Error loading Power Mode session: \(error)")
            #endif
            return nil
        }
    }

    private func clearSession() {
        AppSettings.PowerMode.activeSessionData = nil
    }
    
    deinit {
        // Clean up observer to prevent memory leaks if endSession wasn't called
        NotificationCenter.default.removeObserver(self)
    }
}
