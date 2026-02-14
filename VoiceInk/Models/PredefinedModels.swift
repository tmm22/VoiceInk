import Foundation

enum PredefinedModels {
    static func getLanguageDictionary(isMultilingual: Bool, provider: ModelProvider = .local) -> [String: String] {
        if !isMultilingual {
            return ["en": "English"]
        }

        if provider == .nativeApple {
            let appleSupportedCodes = ["ar", "de", "en", "es", "fr", "it", "ja", "ko", "pt", "yue", "zh"]
            return allLanguages.filter { appleSupportedCodes.contains($0.key) }
        }

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

    static var models: [any TranscriptionModel] {
        // Keep this nonisolated for broad call-site compatibility.
        // Custom models are sourced directly from CustomModelManager in UI flows.
        localModels + cloudModels
    }
}
