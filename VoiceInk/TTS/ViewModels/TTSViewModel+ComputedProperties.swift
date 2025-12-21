import SwiftUI

// MARK: - TTSViewModel Computed Properties

extension TTSViewModel {
    
    // MARK: - Format & Character Limits
    
    /// Returns the supported audio formats for the currently selected provider
    var supportedFormats: [AudioSettings.AudioFormat] {
        supportedFormats(for: selectedProvider)
    }

    /// Returns the character limit for the currently selected provider
    var currentCharacterLimit: Int {
        characterLimit(for: selectedProvider)
    }

    /// Indicates whether any batch segment exceeds the provider's character limit
    var shouldHighlightCharacterOverflow: Bool {
        let limit = currentCharacterLimit
        let segments = batchSegments(from: inputText)
        guard !segments.isEmpty else { return false }
        return segments.contains { $0.count > limit }
    }

    /// Returns the effective character count (excluding batch delimiters)
    var effectiveCharacterCount: Int {
        stripBatchDelimiters(from: inputText).count
    }
    
    // MARK: - Appearance
    
    /// Returns the color scheme override based on user preference
    var colorSchemeOverride: ColorScheme? {
        appearancePreference.colorScheme
    }
    
    // MARK: - Style Controls
    
    /// Indicates whether there are active style controls for the current provider
    var hasActiveStyleControls: Bool {
        !activeStyleControls.isEmpty
    }

    /// Indicates whether any style control can be reset to its default value
    var canResetStyleControls: Bool {
        guard hasActiveStyleControls else { return false }
        return activeStyleControls.contains { canResetStyleControl($0) }
    }
    
    // MARK: - Export Format Help
    
    /// Returns help text describing the export format options for the selected provider
    var exportFormatHelpText: String? {
        switch selectedProvider {
        case .elevenLabs:
            return "ElevenLabs currently exports MP3 files only."
        case .google:
            return "Google Cloud supports MP3 or WAV output."
        case .openAI:
            return "OpenAI offers MP3, WAV, AAC, and FLAC options."
        case .tightAss:
            return "Tight Ass Mode saves audio using the system voices in WAV format."
        }
    }
    
    // MARK: - Batch Processing
    
    /// Indicates whether the input text contains multiple batch segments
    var hasBatchableSegments: Bool {
        batchSegments(from: inputText).count > 1
    }

    /// Returns the number of pending batch segments
    var pendingBatchSegmentCount: Int {
        batchSegments(from: inputText).count
    }
    
    // MARK: - Translation
    
    /// Returns all available translation languages
    var availableTranslationLanguages: [TranslationLanguage] { TranslationLanguage.supported }

    /// Returns the display name for the selected translation target language
    var translationTargetLanguageDisplayName: String { translationTargetLanguage.displayName }

    /// Returns the display name for the detected source language, if available
    var translationDetectedLanguageDisplayName: String? {
        translationResult?.detectedLanguageDisplayName
    }

    /// Indicates whether to show the translation comparison view
    var shouldShowTranslationComparison: Bool {
        translationKeepOriginal && translationResult != nil
    }

    /// Indicates whether translation is available (has credentials)
    var canTranslate: Bool {
        translationService.hasCredentials()
    }
    
    // MARK: - Article Summary
    
    /// Indicates whether article summarization is available (has credentials)
    var canSummarizeImports: Bool {
        summarizationService.hasCredentials()
    }

    /// Returns the article summary preview text, if available
    var articleSummaryPreview: String? {
        articleSummary?.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the condensed import preview text, if available
    var condensedImportPreview: String? {
        articleSummary?.condensedText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns a description of the word reduction achieved by summarization
    var articleSummaryReductionDescription: String? {
        guard let summary = articleSummary,
              let condensedCount = summary.condensedWordCount,
              summary.originalWordCount > 0 else {
            return articleSummary?.wordSavingsDescription
        }

        let reduction = 1 - (Double(condensedCount) / Double(summary.originalWordCount))
        guard reduction > 0 else { return articleSummary?.wordSavingsDescription }
        let percent = Int((reduction * 100).rounded())
        return percent > 0 ? "Cuts roughly \(percent)% of the article before narration." : articleSummary?.wordSavingsDescription
    }

    /// Indicates whether the condensed import can be adopted
    var canAdoptCondensedImport: Bool {
        guard let text = condensedImportPreview else { return false }
        return !text.isEmpty
    }

    /// Indicates whether the summary can be inserted into the editor
    var canInsertSummaryIntoEditor: Bool {
        guard let summary = articleSummaryPreview else { return false }
        return !summary.isEmpty
    }

    /// Indicates whether the summary can be spoken
    var canSpeakSummary: Bool {
        canInsertSummaryIntoEditor
    }
    
    // MARK: - Cost Estimation
    
    /// Returns the cost estimate for the current input text and provider
    var costEstimate: CostEstimate {
        let profile = ProviderCostProfile.profile(for: selectedProvider)
        return profile.estimate(for: effectiveCharacterCount)
    }

    /// Returns a summary string for the cost estimate
    var costEstimateSummary: String { costEstimate.summary }

    /// Returns additional detail for the cost estimate, if available
    var costEstimateDetail: String? { costEstimate.detail }
    
    // MARK: - Transcription Stage
    
    /// Returns a human-readable description of the current transcription stage
    var transcriptionStageDescription: String {
        switch transcriptionStage {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording microphone input"
        case .transcribing:
            return "Transcribing audio with \(selectedTranscriptionProvider.displayName)"
        case .summarising:
            return "Generating insights"
        case .cleaning:
            return "Applying cleanup instructions"
        case .complete:
            return "Transcription complete"
        case .error:
            return "Transcription failed"
        }
    }
    
    // MARK: - Static Helpers
    
    /// Default preview data loader that fetches data from a URL
    static func defaultPreviewLoader(url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw URLError(.unsupportedURL)
        }

        let session = SecureURLSession.makeEphemeral()
        let (data, _) = try await session.data(from: url)
        return data
    }
}
