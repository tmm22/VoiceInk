import Foundation

// MARK: - Provider Capabilities Protocol

/// Protocol defining the capabilities and configuration for each model provider
@MainActor
protocol ProviderCapabilities {
    /// The model provider this capability class handles
    var supportedProvider: ModelProvider { get }

    /// Checks if a model is available/usable for this provider
    /// - Parameter model: The transcription model to check
    /// - Parameter whisperState: The WhisperState instance for context (optional)
    /// - Returns: True if the model is available for use
    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool

    /// Returns the API key name used for Keychain storage
    /// - Returns: The key name for storing API keys, or empty string if no key needed
    func getAPIKeyName() -> String

    /// Returns the corresponding AI service provider (if applicable)
    /// - Returns: The AIProvider enum case, or nil if not applicable
    func getAIServiceProvider() -> AIProvider?
}

// MARK: - Model Capability Registry

/// Registry for managing provider capabilities following SOLID principles
@MainActor
class ModelCapabilityRegistry {
    /// Singleton instance for global access
    static let shared = ModelCapabilityRegistry()

    /// Dictionary mapping providers to their capability implementations
    private var capabilities: [ModelProvider: ProviderCapabilities] = [:]

    private init() {
        registerAllCapabilities()
    }

    /// Register a capability implementation for a provider
    /// - Parameter capability: The capability implementation to register
    func register(_ capability: ProviderCapabilities) {
        capabilities[capability.supportedProvider] = capability
    }

    /// Get the capability implementation for a provider
    /// - Parameter provider: The model provider
    /// - Returns: The capability implementation, or nil if not found
    func getCapabilities(for provider: ModelProvider) -> ProviderCapabilities? {
        capabilities[provider]
    }

    /// Check if a model is available for use
    /// - Parameter model: The transcription model to check
    /// - Parameter whisperState: The WhisperState instance for context
    /// - Returns: True if the model is available
    func isModelAvailable(_ model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        guard let capability = capabilities[model.provider] else {
            return false
        }
        return capability.checkAvailability(model: model, whisperState: whisperState)
    }

    /// Get the API key name for a provider
    /// - Parameter provider: The model provider
    /// - Returns: The API key name, or nil if not found
    func getAPIKeyName(for provider: ModelProvider) -> String? {
        capabilities[provider]?.getAPIKeyName()
    }

    /// Get the AI service provider mapping for a model provider
    /// - Parameter provider: The model provider
    /// - Returns: The corresponding AIProvider, or nil if not applicable
    func getAIServiceProvider(for provider: ModelProvider) -> AIProvider? {
        capabilities[provider]?.getAIServiceProvider()
    }

    /// Register all built-in provider capabilities
    private func registerAllCapabilities() {
        // Local providers
        register(LocalModelCapabilities())
        register(ParakeetModelCapabilities())
        register(FastConformerModelCapabilities())
        register(SenseVoiceModelCapabilities())
        register(NativeAppleModelCapabilities())

        // Cloud providers
        register(GroqModelCapabilities())
        register(ElevenLabsModelCapabilities())
        register(DeepgramModelCapabilities())
        register(MistralModelCapabilities())
        register(GeminiModelCapabilities())
        register(SonioxModelCapabilities())
        register(AssemblyAIModelCapabilities())
        register(ZAIModelCapabilities())

        // Custom providers
        register(CustomModelCapabilities())
    }
}

// MARK: - Local Provider Capabilities

class LocalModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .local

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        guard let whisperState = whisperState, let localModel = model as? LocalModel else {
            return false
        }
        return whisperState.availableModels.contains { $0.name == localModel.name }
    }

    func getAPIKeyName() -> String {
        return ""
    }

    func getAIServiceProvider() -> AIProvider? {
        return nil
    }
}

class ParakeetModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .parakeet

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        guard let whisperState = whisperState, let parakeetModel = model as? ParakeetModel else {
            return false
        }
        return whisperState.isParakeetModelDownloaded(named: parakeetModel.name)
    }

    func getAPIKeyName() -> String {
        return ""
    }

    func getAIServiceProvider() -> AIProvider? {
        return nil
    }
}

class FastConformerModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .fastConformer

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        guard let whisperState = whisperState, let fastModel = model as? FastConformerModel else {
            return false
        }
        return whisperState.isFastConformerModelDownloaded(fastModel)
    }

    func getAPIKeyName() -> String {
        return ""
    }

    func getAIServiceProvider() -> AIProvider? {
        return nil
    }
}

class SenseVoiceModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .senseVoice

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        guard let whisperState = whisperState, let senseVoiceModel = model as? SenseVoiceModel else {
            return false
        }
        return whisperState.isSenseVoiceModelDownloaded(senseVoiceModel)
    }

    func getAPIKeyName() -> String {
        return ""
    }

    func getAIServiceProvider() -> AIProvider? {
        return nil
    }
}

class NativeAppleModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .nativeApple

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        // Native Apple models are available on macOS 15+
        if #available(macOS 15, *) {
            return true
        } else {
            return false
        }
    }

    func getAPIKeyName() -> String {
        return ""
    }

    func getAIServiceProvider() -> AIProvider? {
        return nil
    }
}

// MARK: - Cloud Provider Capabilities

class GroqModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .groq

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "GROQ"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .groq
    }
}

class ElevenLabsModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .elevenLabs

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "ElevenLabs"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .elevenLabs
    }
}

class DeepgramModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .deepgram

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "Deepgram"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .deepgram
    }
}

class MistralModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .mistral

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "Mistral"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .mistral
    }
}

class GeminiModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .gemini

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "Gemini"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .gemini
    }
}

class SonioxModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .soniox

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "Soniox"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .soniox
    }
}

class AssemblyAIModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .assemblyAI

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "AssemblyAI"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .assemblyAI
    }
}

class ZAIModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .zai

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        let keychain = KeychainManager()
        return keychain.hasAPIKey(for: getAPIKeyName())
    }

    func getAPIKeyName() -> String {
        return "ZAI"
    }

    func getAIServiceProvider() -> AIProvider? {
        return .zai
    }
}

class CustomModelCapabilities: ProviderCapabilities {
    let supportedProvider: ModelProvider = .custom

    func checkAvailability(model: any TranscriptionModel, whisperState: WhisperState?) -> Bool {
        // Custom models are always usable since they contain their own API keys
        return true
    }

    func getAPIKeyName() -> String {
        return ""
    }

    func getAIServiceProvider() -> AIProvider? {
        return .custom
    }
}
