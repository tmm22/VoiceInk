import Foundation

/// Central registry for all transcription models available in VoiceInk.
/// Model definitions are organized into extensions:
/// - `PredefinedModels+LocalModels.swift` - Local Whisper, Parakeet, FastConformer, SenseVoice models
/// - `PredefinedModels+CloudModels.swift` - Cloud provider models (Groq, ElevenLabs, Deepgram, etc.)
/// - `PredefinedModels+Languages.swift` - Language dictionaries and Apple Native languages
enum PredefinedModels {
    
    // MARK: - Language Dictionary Helper
    
    /// Returns the appropriate language dictionary based on multilingual support and provider
    /// - Parameters:
    ///   - isMultilingual: Whether the model supports multiple languages
    ///   - provider: The model provider (affects available languages)
    /// - Returns: Dictionary mapping language codes to display names
    static func getLanguageDictionary(isMultilingual: Bool, provider: ModelProvider = .local) -> [String: String] {
        if !isMultilingual {
            return ["en": "English"]
        } else {
            // For Apple Native models, return only supported languages in simple format
            if provider == .nativeApple {
                let appleSupportedCodes = ["ar", "de", "en", "es", "fr", "it", "ja", "ko", "pt", "yue", "zh"]
                return allLanguages.filter { appleSupportedCodes.contains($0.key) }
            }
            // For Soniox, return only the 60 languages supported by stt-async-v4
            if provider == .soniox {
                let sonioxSupportedCodes = [
                    "af", "sq", "ar", "az", "eu", "be", "bn", "bs", "bg", "ca",
                    "zh", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "gl",
                    "de", "el", "gu", "he", "hi", "hu", "id", "it", "ja", "kn",
                    "kk", "ko", "lv", "lt", "mk", "ms", "ml", "mr", "no", "fa",
                    "pl", "pt", "pa", "ro", "ru", "sr", "sk", "sl", "es", "sw",
                    "sv", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy"
                ]
                var filtered = allLanguages.filter { sonioxSupportedCodes.contains($0.key) }
                filtered["auto"] = "Auto-detect"
                return filtered
            }
            return allLanguages
        }
    }
    
    // MARK: - Model Access
    
    /// All available transcription models including predefined and custom models
    @MainActor static var models: [any TranscriptionModel] {
        return predefinedModels + CustomModelManager.shared.customModels
    }
    
    /// Combined array of all predefined models (local + cloud)
    private static let predefinedModels: [any TranscriptionModel] = localModels + cloudModels
}
