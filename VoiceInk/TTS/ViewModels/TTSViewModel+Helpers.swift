import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Core Helper Methods and Utilities
extension TTSViewModel {
    func clearText() {
        cancelBatchGeneration()
        inputText = ""
        stop()
        clearGeneratedAudio()
        batchItems.removeAll()
        batchProgress = 0
        translationResult = nil
        articleSummaryTask?.cancel()
        articleSummaryTask = nil
        articleSummary = nil
        articleSummaryError = nil
        isSummarizingArticle = false
    }
    
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

    func addPronunciationRule(_ rule: PronunciationRule) {
        pronunciationRules.insert(rule, at: 0)
        persistPronunciationRules()
    }

    func updatePronunciationRule(_ rule: PronunciationRule) {
        if let index = pronunciationRules.firstIndex(where: { $0.id == rule.id }) {
            pronunciationRules[index] = rule
            persistPronunciationRules()
        }
    }

    func removePronunciationRule(_ rule: PronunciationRule) {
        pronunciationRules.removeAll { $0.id == rule.id }
        persistPronunciationRules()
    }

    func saveCurrentTextAsSnippet(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else { return }

        textSnippets.removeAll { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }

        let snippet = TextSnippet(name: trimmedName, content: trimmedContent)
        textSnippets.insert(snippet, at: 0)
        persistSnippets()
    }

    func insertSnippet(_ snippet: TextSnippet, mode: SnippetInsertMode) {
        switch mode {
        case .replace:
            inputText = snippet.content
        case .append:
            if inputText.isEmpty {
                inputText = snippet.content
            } else {
                inputText += "\n\n" + snippet.content
            }
        }
    }

    func removeSnippet(_ snippet: TextSnippet) {
        textSnippets.removeAll { $0.id == snippet.id }
        persistSnippets()
    }

    func binding(for control: ProviderStyleControl) -> Binding<Double> {
        Binding(
            get: { self.currentStyleValue(for: control) },
            set: { newValue in
                let clamped = control.clamp(newValue)
                if self.styleValues[control.id] != clamped {
                    self.styleValues[control.id] = clamped
                }
            }
        )
    }

    func currentStyleValue(for control: ProviderStyleControl) -> Double {
        styleValues[control.id] ?? control.defaultValue
    }

    func canResetStyleControl(_ control: ProviderStyleControl) -> Bool {
        abs(currentStyleValue(for: control) - control.defaultValue) > styleComparisonEpsilon
    }
}

// MARK: - Character Limit Helpers
extension TTSViewModel {
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
}

// MARK: - Format and Provider Helpers
extension TTSViewModel {
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

    func clearGeneratedAudio() {
        audioData = nil
        currentAudioFormat = selectedFormat
        currentTranscript = nil
        stop()
    }
}
