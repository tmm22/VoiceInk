import Foundation

// MARK: - Voice Management Helpers
extension TTSViewModel {
    func requestElevenLabsVoices(for model: ElevenLabsModel) {
        elevenLabsVoiceTask?.cancel()

        let provider = elevenLabs
        if let cached = provider.cachedVoices(for: model.rawValue), !cached.isEmpty {
            availableVoices = cached
        } else {
            availableVoices = provider.availableVoices
        }
        reconcileVoiceSelection(with: provider)

        guard provider.hasValidAPIKey() else { return }

        let modelID = model.rawValue
        elevenLabsVoiceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let voices = try await provider.voices(for: modelID)
                try Task.checkCancellation()
                await MainActor.run {
                    self.availableVoices = voices.isEmpty ? provider.availableVoices : voices
                    self.reconcileVoiceSelection(with: provider)
                }
            } catch is CancellationError {
                return
            } catch let error as TTSError {
                guard !Task.isCancelled else { return }
                if case .invalidAPIKey = error {
                    return
                }
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.availableVoices = provider.availableVoices
                    self.reconcileVoiceSelection(with: provider)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.availableVoices = provider.availableVoices
                    self.reconcileVoiceSelection(with: provider)
                }
            }
        }
    }

    func reconcileVoiceSelection(with provider: TTSProvider) {
        if let previewID = previewingVoiceID,
           !availableVoices.contains(where: { $0.id == previewID }) {
            stopPreview()
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

    func ensureValidTranscriptionProviderSelection() {
        if transcriptionServices[selectedTranscriptionProvider] == nil {
            selectedTranscriptionProvider = defaultTranscriptionProvider
        }
    }

    func resolvedTranscriptionService() -> any AudioTranscribing {
        if let service = transcriptionServices[selectedTranscriptionProvider] {
            return service
        }
        if let fallback = transcriptionServices[defaultTranscriptionProvider] {
            return fallback
        }
        
        // Last resort: return any available service or a placeholder
        if let service = transcriptionServices.values.first {
            return service
        }
        
        // Critical error: no services available, but don't crash the app
        #if DEBUG
        print("No transcription services configured - returning placeholder")
        #endif
        
        // Return a placeholder service that will fail gracefully
        return PlaceholderTranscriptionService()
    }
}

// Placeholder service for graceful degradation
private class PlaceholderTranscriptionService: AudioTranscribing {
    func hasCredentials() -> Bool {
        return false
    }
    
    func transcribe(fileURL: URL, languageHint: String?) async throws -> (text: String, language: String?, duration: TimeInterval, segments: [TranscriptionSegment]) {
        throw TTSError.apiError("No transcription service is currently configured. Please check your settings.")
    }
}
