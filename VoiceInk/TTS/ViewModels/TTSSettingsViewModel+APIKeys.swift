import Foundation

extension TTSSettingsViewModel {
    func saveAPIKey(_ key: String, for provider: TTSProviderType) {
        guard provider != .tightAss else { return }
        do {
            try keychainManager.saveAPIKey(key, for: provider.rawValue)
        } catch {
            AppLogger.storage.error("Failed to save \(provider.rawValue, privacy: .public) API key: \(error.localizedDescription)")
            onErrorMessage?("Failed to save API key. Please try again.")
            return
        }

        switch provider {
        case .elevenLabs:
            elevenLabs.updateAPIKey(key)
        case .openAI:
            openAI.updateAPIKey(key)
        case .google:
            googleTTS.updateAPIKey(key)
        case .tightAss:
            break
        }
    }

    func getAPIKey(for provider: TTSProviderType) -> String? {
        guard provider != .tightAss else { return nil }
        return keychainManager.getAPIKey(for: provider.rawValue)
    }
}
