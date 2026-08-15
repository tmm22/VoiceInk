import Foundation

extension TTSSettingsViewModel {
    func persistElevenLabsPrompt() {
        let trimmed = elevenLabsPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AppSettings.TTS.elevenLabsPrompt = nil
        } else {
            AppSettings.TTS.elevenLabsPrompt = trimmed
        }
    }

    func persistElevenLabsModel() {
        AppSettings.TTS.elevenLabsModelRawValue = elevenLabsModel.rawValue
    }

    func persistElevenLabsTags() {
        AppSettings.TTS.elevenLabsTags = elevenLabsTags
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
        elevenLabsVoiceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let voices = try await provider.voices(for: modelID)
                try Task.checkCancellation()
                self.availableVoices = voices.isEmpty ? provider.availableVoices : voices
                self.reconcileVoiceSelection(with: provider)
            } catch is CancellationError {
                return
            } catch let error as TTSError {
                guard !Task.isCancelled else { return }
                if case .invalidAPIKey = error {
                    return
                }
                self.onErrorMessage?(error.localizedDescription)
                self.availableVoices = provider.availableVoices
                self.reconcileVoiceSelection(with: provider)
            } catch {
                guard !Task.isCancelled else { return }
                self.onErrorMessage?(error.localizedDescription)
                self.availableVoices = provider.availableVoices
                self.reconcileVoiceSelection(with: provider)
            }
        }
    }
}
