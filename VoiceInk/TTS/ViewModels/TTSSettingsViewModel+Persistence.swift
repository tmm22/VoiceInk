import Foundation

extension TTSSettingsViewModel {
    func saveSettings() {
        AppSettings.TTS.selectedProviderRawValue = selectedProvider.rawValue
        AppSettings.TTS.playbackSpeed = playback.playbackSpeed
        AppSettings.TTS.volume = playback.volume
        AppSettings.TTS.isLoopEnabled = playback.isLoopEnabled
        AppSettings.TTS.isMinimalistMode = isMinimalistMode
        AppSettings.TTS.selectedAudioFormatRawValue = selectedFormat.rawValue
        AppSettings.TTS.appearancePreferenceRawValue = appearancePreference.rawValue
        AppSettings.TTS.notificationsEnabled = notificationsEnabled
        AppSettings.TTS.inspectorEnabled = isInspectorEnabled
    }

    func loadSavedSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }

        if let savedProvider = AppSettings.TTS.selectedProviderRawValue {
            selectedProvider = TTSProviderType(rawValue: savedProvider) ?? .openAI
        }

        if let savedSpeed = AppSettings.TTS.playbackSpeed {
            playback.playbackSpeed = savedSpeed
        } else {
            playback.playbackSpeed = 1.0
        }

        if let savedVolume = AppSettings.TTS.volume {
            playback.volume = savedVolume
        } else {
            playback.volume = 0.75
        }

        if let loopEnabled = AppSettings.TTS.isLoopEnabled {
            playback.isLoopEnabled = loopEnabled
        }

        if let minimalistMode = AppSettings.TTS.isMinimalistMode {
            isMinimalistMode = minimalistMode
        }

        if let savedFormat = AppSettings.TTS.selectedAudioFormatRawValue,
           let format = AudioSettings.AudioFormat(rawValue: savedFormat) {
            selectedFormat = format
        }

        if let appearanceRaw = AppSettings.TTS.appearancePreferenceRawValue,
           let storedPreference = AppearancePreference(rawValue: appearanceRaw) {
            appearancePreference = storedPreference
        }

        if let styleData = AppSettings.TTS.styleValuesData {
            do {
                let decoded = try JSONDecoder().decode([String: [String: Double]].self, from: styleData)
                cachedStyleValues = decoded.reduce(into: [:]) { partialResult, element in
                    guard let provider = TTSProviderType(rawValue: element.key) else { return }
                    partialResult[provider] = element.value
                }
            } catch {
                cachedStyleValues = [:]
            }
        }

        if let snippetsData = AppSettings.TTS.snippetsData {
            do {
                let decoded = try JSONDecoder().decode([TextSnippet].self, from: snippetsData)
                textSnippets = decoded
            } catch {
                textSnippets = []
            }
        }

        if let pronunciationData = AppSettings.TTS.pronunciationRulesData {
            do {
                let decoded = try JSONDecoder().decode([PronunciationRule].self, from: pronunciationData)
                pronunciationRules = decoded
            } catch {
                pronunciationRules = []
            }
        }

        if let notifications = AppSettings.TTS.notificationsEnabled {
            notificationsEnabled = notifications
        }

        if let inspectorEnabled = AppSettings.TTS.inspectorEnabled {
            isInspectorEnabled = inspectorEnabled
        }

        if notificationCenter == nil && notificationsEnabled {
            notificationsEnabled = false
            saveSettings()
        }

        notificationCenter?.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            let authorizationStatus = settings.authorizationStatus
            Task { @MainActor in
                if authorizationStatus != .authorized && self.notificationsEnabled {
                    self.notificationsEnabled = false
                    self.saveSettings()
                }
            }
        }

        if let savedPrompt = AppSettings.TTS.elevenLabsPrompt {
            elevenLabsPrompt = savedPrompt
        }

        if let savedModelID = AppSettings.TTS.elevenLabsModelRawValue,
           let savedModel = ElevenLabsModel(rawValue: savedModelID) {
            elevenLabsModel = savedModel
        }

        if let storedTags = AppSettings.TTS.elevenLabsTags {
            elevenLabsTags = storedTags
        } else {
            normalizeElevenLabsTagsIfNeeded()
        }

        managedProvisioningEnabled = managedProvisioningClient.isEnabled
        managedProvisioningConfiguration = managedProvisioningClient.configuration

        playback.applyPlaybackSettings()
        ensureFormatSupportedForSelectedProvider()

        if let elevenLabsKey = getAPIKey(for: .elevenLabs) {
            elevenLabs.updateAPIKey(elevenLabsKey)
        }
        if let openAIKey = getAPIKey(for: .openAI) {
            openAI.updateAPIKey(openAIKey)
        }
        if let googleKey = getAPIKey(for: .google) {
            googleTTS.updateAPIKey(googleKey)
        }
    }
}
