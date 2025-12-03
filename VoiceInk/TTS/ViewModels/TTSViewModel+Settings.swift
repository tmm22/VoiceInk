import SwiftUI
import UserNotifications

// MARK: - Settings Persistence and Style Controls
extension TTSViewModel {
    func resetStyleControl(_ control: ProviderStyleControl) {
        guard hasActiveStyleControls else { return }
        guard canResetStyleControl(control) else { return }
        styleValues[control.id] = control.defaultValue
    }

    func resetStyleControls() {
        guard hasActiveStyleControls else { return }
        let defaults = activeStyleControls.reduce(into: [String: Double]()) { partialResult, control in
            partialResult[control.id] = control.defaultValue
        }
        styleValues = defaults
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }

        guard let notificationCenter else {
            notificationsEnabled = false
            saveSettings()
            return
        }

        if enabled {
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.notificationsEnabled = granted
                    self.saveSettings()
                }
            }
        } else {
            notificationsEnabled = false
            saveSettings()
        }
    }

    func saveAPIKey(_ key: String, for provider: TTSProviderType) {
        guard provider != .tightAss else { return }
        keychainManager.saveAPIKey(key, for: provider.rawValue)
        
        // Update the service with new key
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

    func saveSettings() {
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedProvider")
        UserDefaults.standard.set(selectedTranscriptionProvider.rawValue, forKey: transcriptionProviderKey)
        UserDefaults.standard.set(playbackSpeed, forKey: "playbackSpeed")
        UserDefaults.standard.set(volume, forKey: "volume")
        UserDefaults.standard.set(isLoopEnabled, forKey: "loopEnabled")
        UserDefaults.standard.set(isMinimalistMode, forKey: "isMinimalistMode")
        UserDefaults.standard.set(selectedFormat.rawValue, forKey: "audioFormat")
        UserDefaults.standard.set(appearancePreference.rawValue, forKey: "appearancePreference")
        UserDefaults.standard.set(notificationsEnabled, forKey: notificationsKey)
        UserDefaults.standard.set(isInspectorEnabled, forKey: inspectorEnabledKey)
    }

    func updateManagedProvisioningConfiguration(baseURL: String, accountId: String, planTier: String, planStatus: String, enabled: Bool) {
        guard let url = URL(string: baseURL) else {
            managedProvisioningError = "Invalid provisioning URL"
            return
        }

        let configuration = ManagedProvisioningClient.Configuration(
            baseURL: url,
            accountId: accountId,
            planTier: planTier.lowercased(),
            planStatus: planStatus.lowercased()
        )
        managedProvisioningClient.configuration = configuration
        managedProvisioningClient.isEnabled = enabled
        managedProvisioningClient.invalidateAllCredentials()
        managedProvisioningConfiguration = configuration
        managedProvisioningEnabled = enabled
        managedProvisioningError = nil

        managedProvisioningTask?.cancel()
        managedProvisioningTask = Task { [weak self] in
            await self?.refreshManagedAccountSnapshot(silently: true)
        }
    }

    func clearManagedProvisioning() {
        managedProvisioningTask?.cancel()
        managedProvisioningTask = nil
        managedProvisioningClient.reset()
        managedProvisioningConfiguration = nil
        managedProvisioningEnabled = false
        managedAccountSnapshot = nil
        managedProvisioningError = nil
    }

    func refreshManagedAccountSnapshot(silently: Bool = false) async {
        guard managedProvisioningClient.isEnabled, managedProvisioningClient.configuration != nil else {
            managedAccountSnapshot = nil
            if !silently {
                managedProvisioningError = "Managed provisioning is disabled."
            }
            return
        }

        do {
            let snapshot = try await managedProvisioningClient.fetchAccountSnapshot()
            managedAccountSnapshot = snapshot
            managedProvisioningError = nil
        } catch {
            if !silently {
                managedProvisioningError = error.localizedDescription
            }
        }
    }
}

// MARK: - Settings Private Helpers
extension TTSViewModel {
    func loadSavedSettings() {
        // Load from UserDefaults
        if let savedProvider = UserDefaults.standard.string(forKey: "selectedProvider") {
            selectedProvider = TTSProviderType(rawValue: savedProvider) ?? .openAI
        }

        if let savedTranscriptionProvider = UserDefaults.standard.string(forKey: transcriptionProviderKey),
           let provider = TranscriptionProviderType(rawValue: savedTranscriptionProvider),
           transcriptionServices[provider] != nil {
            selectedTranscriptionProvider = provider
        } else {
            selectedTranscriptionProvider = defaultTranscriptionProvider
        }

        playbackSpeed = UserDefaults.standard.double(forKey: "playbackSpeed")
        if playbackSpeed == 0 { playbackSpeed = 1.0 }
        
        volume = UserDefaults.standard.double(forKey: "volume")
        if volume == 0 { volume = 0.75 }
        
        isLoopEnabled = UserDefaults.standard.bool(forKey: "loopEnabled")
        isMinimalistMode = UserDefaults.standard.bool(forKey: "isMinimalistMode")
        if let savedFormat = UserDefaults.standard.string(forKey: "audioFormat"),
           let format = AudioSettings.AudioFormat(rawValue: savedFormat) {
            selectedFormat = format
        }

        if let appearanceRaw = UserDefaults.standard.string(forKey: "appearancePreference"),
           let storedPreference = AppearancePreference(rawValue: appearanceRaw) {
            appearancePreference = storedPreference
        }

        if let styleData = UserDefaults.standard.data(forKey: styleValuesKey) {
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

        if let snippetsData = UserDefaults.standard.data(forKey: snippetsKey) {
            do {
                let decoded = try JSONDecoder().decode([TextSnippet].self, from: snippetsData)
                textSnippets = decoded
            } catch {
                textSnippets = []
            }
        }

        if let pronunciationData = UserDefaults.standard.data(forKey: pronunciationKey) {
            do {
                let decoded = try JSONDecoder().decode([PronunciationRule].self, from: pronunciationData)
                pronunciationRules = decoded
            } catch {
                pronunciationRules = []
            }
        }

        notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsKey)
        isInspectorEnabled = UserDefaults.standard.bool(forKey: inspectorEnabledKey)

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

        if let savedPrompt = UserDefaults.standard.string(forKey: elevenLabsPromptKey) {
            elevenLabsPrompt = savedPrompt
        }

        if let savedModelID = UserDefaults.standard.string(forKey: elevenLabsModelKey),
           let savedModel = ElevenLabsModel(rawValue: savedModelID) {
            elevenLabsModel = savedModel
        }

        if let storedTags = UserDefaults.standard.array(forKey: elevenLabsTagsKey) as? [String] {
            elevenLabsTags = storedTags
        } else {
            normalizeElevenLabsTagsIfNeeded()
        }

        managedProvisioningEnabled = managedProvisioningClient.isEnabled
        managedProvisioningConfiguration = managedProvisioningClient.configuration

        applyPlaybackSettings()

        ensureFormatSupportedForSelectedProvider()

        // Load API keys from keychain
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

    func refreshStyleControls(for providerType: TTSProviderType) {
        let provider = getProvider(for: providerType)
        let controls = provider.styleControls
        activeStyleControls = controls

        guard !controls.isEmpty else {
            styleValues = [:]
            cachedStyleValues[providerType] = [:]
            return
        }

        let resolved = resolveStyleValues(for: controls, cached: cachedStyleValues[providerType])
        styleValues = resolved
    }

    func resolveStyleValues(for controls: [ProviderStyleControl], cached: [String: Double]?) -> [String: Double] {
        controls.reduce(into: [:]) { partialResult, control in
            let stored = cached?[control.id] ?? control.defaultValue
            partialResult[control.id] = control.clamp(stored)
        }
    }

    func styleValues(for providerType: TTSProviderType) -> [String: Double] {
        if providerType == selectedProvider {
            return styleValues
        }

        let provider = getProvider(for: providerType)
        let controls = provider.styleControls
        guard !controls.isEmpty else {
            cachedStyleValues[providerType] = [:]
            persistStyleValues()
            return [:]
        }
        let resolved = resolveStyleValues(for: controls, cached: cachedStyleValues[providerType])
        cachedStyleValues[providerType] = resolved
        persistStyleValues()
        return resolved
    }

    func persistStyleValues() {
        let filtered = cachedStyleValues.reduce(into: [String: [String: Double]]()) { partialResult, element in
            guard !element.value.isEmpty else { return }
            partialResult[element.key.rawValue] = element.value
        }

        let defaults = UserDefaults.standard
        if filtered.isEmpty {
            defaults.removeObject(forKey: styleValuesKey)
            return
        }

        if let data = try? JSONEncoder().encode(filtered) {
            defaults.set(data, forKey: styleValuesKey)
        }
    }

    func persistElevenLabsPrompt() {
        let defaults = UserDefaults.standard
        let trimmed = elevenLabsPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: elevenLabsPromptKey)
        } else {
            defaults.set(trimmed, forKey: elevenLabsPromptKey)
        }
    }

    func persistElevenLabsModel() {
        UserDefaults.standard.set(elevenLabsModel.rawValue, forKey: elevenLabsModelKey)
    }

    func persistElevenLabsTags() {
        UserDefaults.standard.set(elevenLabsTags, forKey: elevenLabsTagsKey)
    }

    func normalizeElevenLabsTagsIfNeeded() {
        guard !isNormalizingElevenLabsTags else { return }
        isNormalizingElevenLabsTags = true
        defer { isNormalizingElevenLabsTags = false }

        var seen = Set<String>()
        let normalized = elevenLabsTags.compactMap { token -> String? in
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if seen.insert(trimmed).inserted {
                return trimmed
            }
            return nil
        }

        if normalized != elevenLabsTags {
            elevenLabsTags = normalized
        }
    }
}