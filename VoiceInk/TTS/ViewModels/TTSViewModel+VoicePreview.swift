import SwiftUI
import AVFoundation

// MARK: - Voice Preview Controls
extension TTSViewModel {
    func previewVoice(_ voice: Voice) {
        if previewingVoiceID == voice.id && (isPreviewing || isPreviewLoading) {
            stopPreview()
            return
        }

        stopPreview()

        guard let providerType = TTSProviderType(rawValue: voice.provider.rawValue) else {
            errorMessage = "Preview not available for \(voice.name)."
            return
        }

        audioPlayer.pause()
        isPlaying = false
        previewingVoiceID = voice.id
        previewVoiceName = voice.name
        isPreviewLoading = true

        previewTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let data = try await self.loadPreviewAudio(for: voice, providerType: providerType)
                try Task.checkCancellation()
                try await self.previewPlayer.loadAudio(from: data)
                try Task.checkCancellation()
                self.previewPlayer.setVolume(Float(self.volume))
                self.previewPlayer.play()
                self.isPreviewLoading = false
                self.isPreviewing = true
            } catch is CancellationError {
                self.resetPreviewState()
            } catch {
                self.handlePreviewError(error, voiceName: voice.name)
            }

            self.previewTask = nil
        }
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewPlayer.stop()
        resetPreviewState()
    }

    func isPreviewingVoice(_ voice: Voice) -> Bool {
        previewingVoiceID == voice.id && isPreviewing
    }

    func isPreviewLoadingVoice(_ voice: Voice) -> Bool {
        previewingVoiceID == voice.id && isPreviewLoading
    }

    func canPreview(_ voice: Voice) -> Bool {
        if voice.previewURL != nil {
            return true
        }

        guard let providerType = TTSProviderType(rawValue: voice.provider.rawValue) else {
            return false
        }

        if providerType == .tightAss {
            return true
        }

        let provider = getProvider(for: providerType)
        return provider.hasValidAPIKey()
    }

    var isPreviewActive: Bool {
        previewingVoiceID != nil
    }

    var isPreviewPlaying: Bool {
        previewingVoiceID != nil && isPreviewing
    }

    var isPreviewLoadingActive: Bool {
        previewingVoiceID != nil && isPreviewLoading
    }
}

// MARK: - Voice Preview Private Helpers
extension TTSViewModel {
    func loadPreviewAudio(for voice: Voice, providerType: TTSProviderType) async throws -> Data {
        if let previewURLString = voice.previewURL,
           let url = URL(string: previewURLString) {
            return try await previewDataLoader(url)
        }

        var settings = previewAudioSettings(for: providerType)
        let resolvedStyleValues = styleValues(for: providerType)
        settings.styleValues = resolvedStyleValues

        if let generator = previewAudioGenerator {
            return try await generator(voice, providerType, settings, resolvedStyleValues)
        }

        let provider = getProvider(for: providerType)

        if providerType != .tightAss && !provider.hasValidAPIKey() {
            throw VoicePreviewError.missingAPIKey(providerName: providerType.displayName)
        }

        return try await synthesizeSpeechWithFallback(
            text: previewSampleText(for: voice, providerType: providerType),
            voice: voice,
            provider: provider,
            providerType: providerType,
            settings: settings
        )
    }

    func resetPreviewState() {
        previewTask = nil
        previewingVoiceID = nil
        previewVoiceName = nil
        isPreviewLoading = false
        isPreviewing = false
    }

    func handlePreviewError(_ error: Error, voiceName: String?) {
        let resolvedName = voiceName ?? previewVoiceName ?? "this voice"
        errorMessage = "Unable to preview \(resolvedName): \(error.localizedDescription)"
        resetPreviewState()
    }

    func previewAudioSettings(for providerType: TTSProviderType) -> AudioSettings {
        var settings = AudioSettings()
        settings.speed = min(max(playbackSpeed, 0.5), 2.0)
        settings.pitch = 1.0
        settings.volume = min(max(volume, 0.0), 1.0)
        settings.sampleRate = providerType == .google ? 24_000 : 22_050
        settings.format = providerType == .tightAss ? .wav : .mp3
        if providerType == .elevenLabs {
            settings.providerOptions[ElevenLabsProviderOptionKey.modelID] = elevenLabsModel.rawValue
        }
        return settings
    }

    func previewSampleText(for voice: Voice, providerType: TTSProviderType) -> String {
        "Hello, this is \(voice.name) with \(providerType.displayName). Here's a quick preview."
    }
}

// MARK: - Voice Preview Error
private enum VoicePreviewError: LocalizedError {
    case missingAPIKey(providerName: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let providerName):
            return "\(providerName) API key is required to preview this voice."
        }
    }
}