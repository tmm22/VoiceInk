import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Helper Methods and Utilities
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

    func exportAudio() {
        guard audioData != nil else { return }

        guard let panelChoice = configuredSavePanel(
            defaultFormat: currentAudioFormat,
            provider: selectedProvider
        ) else { return }

        let (savePanel, orderedFormats) = panelChoice

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let chosenExtension = url.pathExtension.isEmpty ? currentAudioFormat.fileExtension : url.pathExtension
            let chosenFormat = AudioSettings.AudioFormat(fileExtension: chosenExtension) ?? orderedFormats.first ?? currentAudioFormat

            Task { [weak self] in
                await self?.performExport(to: url, format: chosenFormat)
            }
        }
    }

    func exportTranscript(format: TranscriptFormat) {
        guard let transcript = currentTranscript else { return }
        exportTranscriptBundle(transcript, format: format, suggestedName: "transcript")
    }

    func exportTranscript(for item: GenerationHistoryItem, format: TranscriptFormat) {
        guard let transcript = item.transcript else { return }
        let baseName = item.voice.name.replacingOccurrences(of: " ", with: "-").lowercased()
        exportTranscriptBundle(transcript, format: format, suggestedName: "transcript-\(baseName)")
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

// MARK: - ElevenLabs Prompting Helpers
extension TTSViewModel {
    func insertElevenLabsPromptAtTop() {
        let trimmedPrompt = elevenLabsPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        let promptBlock = "\(trimmedPrompt)\n\n"
        let existing = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        if existing.lowercased().hasPrefix(trimmedPrompt.lowercased()) {
            return
        }

        if existing.isEmpty {
            inputText = promptBlock
        } else {
            inputText = promptBlock + inputText
        }
    }

    func insertElevenLabsTag(_ rawToken: String) {
        let normalized = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if inputText.isEmpty {
            inputText = normalized
        } else if inputText.hasSuffix("\n") {
            inputText.append(contentsOf: "\(normalized)\n")
        } else {
            inputText.append(contentsOf: "\n\(normalized)\n")
        }
    }

    func addElevenLabsTag(_ rawToken: String) {
        var normalized = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if !normalized.hasPrefix("[") {
            normalized = "[\(normalized)"
        }
        if !normalized.hasSuffix("]") {
            normalized.append("]")
        }

        guard !elevenLabsTags.contains(normalized) else { return }
        elevenLabsTags.append(normalized)
    }

    func removeElevenLabsTag(_ token: String) {
        elevenLabsTags.removeAll { $0 == token }
    }

    func resetElevenLabsTagsToDefaults() {
        elevenLabsTags = ElevenLabsVoiceTag.defaultTokens
    }
}

// MARK: - Batch and Text Processing Helpers
extension TTSViewModel {
    func persistSnippets() {
        do {
            let data = try JSONEncoder().encode(textSnippets)
            UserDefaults.standard.set(data, forKey: snippetsKey)
        } catch {
            // If persistence fails, keep in-memory state for this session
        }
    }

    func persistPronunciationRules() {
        do {
            let data = try JSONEncoder().encode(pronunciationRules)
            UserDefaults.standard.set(data, forKey: pronunciationKey)
        } catch {
            // If persistence fails, keep the in-memory rules this session
        }
    }

    func shouldAllowCharacterOverflow(for text: String) -> Bool {
        let limit = characterLimit(for: selectedProvider)
        let segments = batchSegments(from: text)
        guard !segments.isEmpty else { return false }
        guard segments.count > 1 else { return false }
        return segments.allSatisfy { $0.count <= limit }
    }

    func batchSegments(from text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var segments: [String] = []
        var currentLines: [String] = []

        func flushCurrentSegment() {
            let segment = currentLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                segments.append(segment)
            }
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == batchDelimiterToken {
                flushCurrentSegment()
            } else {
                currentLines.append(line)
            }
        }

        flushCurrentSegment()
        return segments
    }

    func stripBatchDelimiters(from text: String) -> String {
        guard !text.isEmpty else { return text }

        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        let filteredLines = normalized
            .components(separatedBy: "\n")
            .filter { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines) != batchDelimiterToken
            }
        let joined = filteredLines.joined(separator: "\n")
        return joined
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func applyPronunciationRules(to text: String, provider: TTSProviderType) -> String {
        pronunciationRules.reduce(text) { current, rule in
            guard rule.applies(to: provider) else { return current }
            return replaceOccurrences(in: current, target: rule.displayText, replacement: rule.replacementText)
        }
    }

    func replaceOccurrences(in text: String, target: String, replacement: String) -> String {
        guard !target.isEmpty else { return text }
        var result = text
        var searchRange = result.startIndex..<result.endIndex

        while let range = result.range(of: target, options: [.caseInsensitive], range: searchRange) {
            result.replaceSubrange(range, with: replacement)
            if replacement.isEmpty {
                searchRange = range.lowerBound..<result.endIndex
            } else {
                let nextIndex = result.index(range.lowerBound, offsetBy: replacement.count)
                searchRange = nextIndex..<result.endIndex
            }
        }

        return result
    }

    func sendBatchCompletionNotification(successCount: Int, failureCount: Int) {
        guard notificationsEnabled, successCount + failureCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Batch Generation Complete"

        if failureCount == 0 {
            content.body = "All \(successCount) segment(s) generated successfully."
        } else if successCount == 0 {
            content.body = "Batch generation failed for all \(failureCount) segment(s)."
        } else {
            content.body = "\(successCount) succeeded • \(failureCount) failed."
        }

        let request = UNNotificationRequest(
            identifier: "batch-complete-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        notificationCenter?.add(request)
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

    func configuredSavePanel(defaultFormat: AudioSettings.AudioFormat,
                             provider: TTSProviderType) -> (NSSavePanel, [AudioSettings.AudioFormat])? {
        let savePanel = NSSavePanel()
        let providerFormats = supportedFormats(for: provider)
        let orderedFormats: [AudioSettings.AudioFormat]

        if let currentIndex = providerFormats.firstIndex(of: defaultFormat) {
            var formats = providerFormats
            formats.swapAt(0, currentIndex)
            orderedFormats = formats
        } else {
            orderedFormats = providerFormats
        }

        let contentTypes = orderedFormats.compactMap { $0.contentType }
        if !contentTypes.isEmpty {
            savePanel.allowedContentTypes = contentTypes
            savePanel.allowsOtherFileTypes = false
        }

        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "speech.\(defaultFormat.fileExtension)"
        savePanel.title = "Export Audio"
        savePanel.message = "Choose where to save the audio file"

        return (savePanel, orderedFormats)
    }

    func exportTranscriptBundle(_ transcript: TranscriptBundle,
                                format: TranscriptFormat,
                                suggestedName: String) {
        let savePanel = NSSavePanel()
        if let contentType = format.contentType {
            savePanel.allowedContentTypes = [contentType]
            savePanel.allowsOtherFileTypes = false
        }
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        savePanel.title = "Export Transcript"
        savePanel.message = "Choose where to save the transcript file"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            var destination = url
            let expectedExtension = format.fileExtension
            if destination.pathExtension.lowercased() != expectedExtension {
                destination = url.deletingPathExtension().appendingPathExtension(expectedExtension)
            }

            let content: String = {
                switch format {
                case .srt:
                    return transcript.srt
                case .vtt:
                    return transcript.vtt
                }
            }()

            do {
                try Data(content.utf8).write(to: destination, options: .atomic)
            } catch {
                errorMessage = "Failed to save transcript: \(error.localizedDescription)"
            }
        }
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

    func performExport(to url: URL, format: AudioSettings.AudioFormat) async {
        do {
            let data = try await dataForExport(using: format)
            var destinationURL = url
            let expectedExtension = format.fileExtension

            if destinationURL.pathExtension.lowercased() != expectedExtension {
                destinationURL = url.deletingPathExtension().appendingPathExtension(expectedExtension)
            }

            try data.write(to: destinationURL, options: .atomic)
        } catch let error as TTSError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to save audio: \(error.localizedDescription)"
        }
    }

    func dataForExport(using format: AudioSettings.AudioFormat) async throws -> Data {
        if format == currentAudioFormat, let data = audioData {
            return data
        }

        guard !inputText.isEmpty else {
            throw TTSError.apiError("No text available to regenerate audio for export.")
        }

        let provider = getCurrentProvider()
        let providerType = selectedProvider
        guard provider.hasValidAPIKey() else {
            throw TTSError.invalidAPIKey
        }

        let voice = selectedVoice ?? provider.defaultVoice
        var settings = AudioSettings(
            speed: playbackSpeed,
            volume: volume,
            format: format,
            sampleRate: sampleRate(for: format),
            styleValues: styleValues(for: selectedProvider)
        )

        if selectedProvider == .elevenLabs {
            settings.providerOptions[ElevenLabsProviderOptionKey.modelID] = elevenLabsModel.rawValue
        }

        let previousAudioData = audioData
        let previousFormat = currentAudioFormat

        isGenerating = true
        generationProgress = 0.2
        errorMessage = nil

        defer {
            isGenerating = false
            generationProgress = 0
        }

        do {
            let newData = try await synthesizeSpeechWithFallback(
                text: inputText,
                voice: voice,
                provider: provider,
                providerType: providerType,
                settings: settings
            )

            generationProgress = 0.9
            try await audioPlayer.loadAudio(from: newData)

            audioData = newData
            currentAudioFormat = format

            if selectedFormat != format {
                selectedFormat = format
            }

            return newData
        } catch let error as TTSError {
            audioData = previousAudioData
            currentAudioFormat = previousFormat

            if let previousAudioData {
                try? await audioPlayer.loadAudio(from: previousAudioData)
            } else {
                stop()
            }

            throw error
        } catch {
            audioData = previousAudioData
            currentAudioFormat = previousFormat

            if let previousAudioData {
                try? await audioPlayer.loadAudio(from: previousAudioData)
            } else {
                stop()
            }

            throw TTSError.apiError("Failed to regenerate audio: \(error.localizedDescription)")
        }
    }
}

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