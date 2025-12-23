import Foundation

extension TTSSettingsViewModel {
    func updateAvailableVoices() {
        let provider = getCurrentProvider()
        if selectedProvider == .elevenLabs {
            requestElevenLabsVoices(for: elevenLabsModel)
        } else {
            elevenLabsVoiceTask?.cancel()
            availableVoices = provider.availableVoices
            reconcileVoiceSelection(with: provider)
        }
        refreshStyleControls(for: selectedProvider)
        ensureFormatSupportedForSelectedProvider()
    }

    func reconcileVoiceSelection(with provider: TTSProvider) {
        if let previewID = preview.previewingVoiceID,
           !availableVoices.contains(where: { $0.id == previewID }) {
            preview.stopPreview()
        }

        if let selected = selectedVoice,
           !availableVoices.contains(selected) {
            selectedVoice = nil
        }

        if selectedVoice == nil {
            if availableVoices.contains(provider.defaultVoice) {
                selectedVoice = provider.defaultVoice
            } else if let first = availableVoices.first {
                selectedVoice = first
            } else {
                selectedVoice = provider.defaultVoice
            }
        }
    }

    func characterLimit(for provider: TTSProviderType) -> Int {
        if let limit = providerCharacterLimits[provider] {
            return limit
        }
        return providerCharacterLimits.values.max() ?? 5_000
    }

    func formattedCharacterLimit(for provider: TTSProviderType) -> String {
        let limit = characterLimit(for: provider)
        return Self.characterCountFormatter.string(from: NSNumber(value: limit)) ?? "\(limit)"
    }

    func getProvider(for type: TTSProviderType) -> any TTSProvider {
        switch type {
        case .elevenLabs:
            return elevenLabs
        case .openAI:
            return openAI
        case .google:
            return googleTTS
        case .tightAss:
            return localTTS
        }
    }

    func getCurrentProvider() -> any TTSProvider {
        getProvider(for: selectedProvider)
    }

    func currentFormatForGeneration() -> AudioSettings.AudioFormat {
        let formats = supportedFormats(for: selectedProvider)
        guard formats.contains(selectedFormat) else {
            return formats.first ?? .mp3
        }
        return selectedFormat
    }

    func supportedFormats(for provider: TTSProviderType) -> [AudioSettings.AudioFormat] {
        switch provider {
        case .elevenLabs:
            return [.mp3]
        case .openAI:
            return [.mp3, .wav, .aac, .flac]
        case .google:
            return [.mp3, .wav]
        case .tightAss:
            return [.wav]
        }
    }

    func sampleRate(for format: AudioSettings.AudioFormat) -> Int {
        switch format {
        case .wav, .flac:
            return 44100
        case .aac:
            return 48000
        case .mp3:
            return 44100
        case .opus:
            return 48000
        }
    }

    func ensureFormatSupportedForSelectedProvider() {
        let formats = supportedFormats(for: selectedProvider)
        if !formats.contains(selectedFormat) {
            selectedFormat = formats.first ?? .mp3
        }
    }
}
