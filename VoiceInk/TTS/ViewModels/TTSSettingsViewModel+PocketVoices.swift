import Foundation

extension TTSSettingsViewModel {
    var hasHiddenPocketVoices: Bool {
        !hiddenPocketVoiceIDs.isEmpty
    }

    var canHideSelectedPocketVoice: Bool {
        guard let selectedVoice else { return false }
        return LocalTTSService.isPocketVoiceID(selectedVoice.id) && !hiddenPocketVoiceIDs.contains(selectedVoice.id)
    }

    var sortedHiddenPocketVoiceIDs: [String] {
        hiddenPocketVoiceIDs.sorted { lhs, rhs in
            pocketVoiceDisplayName(for: lhs) < pocketVoiceDisplayName(for: rhs)
        }
    }

    func pocketVoiceDisplayName(for id: String) -> String {
        LocalTTSService.pocketVoiceName(for: id) ?? id
    }

    func isPocketVoiceHidden(_ voice: Voice) -> Bool {
        hiddenPocketVoiceIDs.contains(voice.id)
    }

    func visibleVoices(from voices: [Voice], providerType: TTSProviderType) -> [Voice] {
        guard providerType == .tightAss else { return voices }
        guard !hiddenPocketVoiceIDs.isEmpty else { return voices }
        return voices.filter { voice in
            !(LocalTTSService.isPocketVoiceID(voice.id) && hiddenPocketVoiceIDs.contains(voice.id))
        }
    }

    func hideSelectedPocketVoice() {
        guard let selectedVoice else { return }
        hidePocketVoice(selectedVoice)
    }

    func hidePocketVoice(_ voice: Voice) {
        guard LocalTTSService.isPocketVoiceID(voice.id) else { return }
        guard hiddenPocketVoiceIDs.insert(voice.id).inserted else { return }

        if preview.previewingVoiceID == voice.id {
            preview.stopPreview()
        }

        Task.detached(priority: .utility) {
            do {
                try await LocalTTSService.removeCachedPocketVoiceEmbedding(for: voice.id)
            } catch {
                AppLogger.audio.warning("Failed to remove cached Pocket voice embedding for \(voice.id): \(error.localizedDescription)")
            }
        }
    }

    func restorePocketVoice(withID id: String) {
        guard hiddenPocketVoiceIDs.contains(id) else { return }
        hiddenPocketVoiceIDs.remove(id)
    }

    func restoreAllPocketVoices() {
        guard !hiddenPocketVoiceIDs.isEmpty else { return }
        hiddenPocketVoiceIDs.removeAll()
    }

    func persistHiddenPocketVoiceIDs() {
        if hiddenPocketVoiceIDs.isEmpty {
            AppSettings.TTS.hiddenPocketVoiceIDs = nil
        } else {
            AppSettings.TTS.hiddenPocketVoiceIDs = hiddenPocketVoiceIDs.sorted()
        }

        if selectedProvider == .tightAss {
            updateAvailableVoices()
        }
    }
}
