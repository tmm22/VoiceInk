// MARK: - Core Helper Methods and Utilities
extension TTSViewModel {
    func clearText() {
        generation.cancelBatchGeneration()
        inputText = ""
        playback.stop()
        clearGeneratedAudio()
        generation.batchItems.removeAll()
        generation.batchProgress = 0
        translationResult = nil
        importExport.clearArticleSummary()
    }
    
    func updateAvailableVoices() {
        settings.updateAvailableVoices()
    }

    func addPronunciationRule(_ rule: PronunciationRule) {
        settings.addPronunciationRule(rule)
    }

    func updatePronunciationRule(_ rule: PronunciationRule) {
        settings.updatePronunciationRule(rule)
    }

    func removePronunciationRule(_ rule: PronunciationRule) {
        settings.removePronunciationRule(rule)
    }

    func saveCurrentTextAsSnippet(named name: String) {
        settings.saveSnippet(named: name, content: inputText)
    }

    func insertSnippet(_ snippet: TextSnippet, mode: SnippetInsertMode) {
        inputText = settings.insertSnippet(snippet, into: inputText, mode: mode)
    }

    func removeSnippet(_ snippet: TextSnippet) {
        settings.removeSnippet(snippet)
    }
}

// MARK: - Character Limit Helpers
extension TTSViewModel {
    func characterLimit(for provider: TTSProviderType) -> Int {
        settings.characterLimit(for: provider)
    }

    func formattedCharacterLimit(for provider: TTSProviderType) -> String {
        settings.formattedCharacterLimit(for: provider)
    }
}

// MARK: - Format and Provider Helpers
extension TTSViewModel {
    func getProvider(for type: TTSProviderType) -> any TTSProvider {
        settings.getProvider(for: type)
    }

    func getCurrentProvider() -> any TTSProvider {
        settings.getCurrentProvider()
    }

    func currentFormatForGeneration() -> AudioSettings.AudioFormat {
        settings.currentFormatForGeneration()
    }

    func supportedFormats(for provider: TTSProviderType) -> [AudioSettings.AudioFormat] {
        settings.supportedFormats(for: provider)
    }

    func sampleRate(for format: AudioSettings.AudioFormat) -> Int {
        settings.sampleRate(for: format)
    }

    func ensureFormatSupportedForSelectedProvider() {
        settings.ensureFormatSupportedForSelectedProvider()
    }

    func styleValues(for provider: TTSProviderType) -> [String: Double] {
        settings.styleValues(for: provider)
    }

    func clearGeneratedAudio() {
        audioData = nil
        currentAudioFormat = settings.selectedFormat
        currentTranscript = nil
        playback.stop()
    }
}
