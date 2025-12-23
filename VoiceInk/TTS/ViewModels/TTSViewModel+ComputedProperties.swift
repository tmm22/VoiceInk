import SwiftUI

// MARK: - TTSViewModel Computed Properties

extension TTSViewModel {
    
    // MARK: - Format & Character Limits
    
    /// Returns the supported audio formats for the currently selected provider
    var supportedFormats: [AudioSettings.AudioFormat] {
        settings.supportedFormats(for: settings.selectedProvider)
    }

    /// Returns the character limit for the currently selected provider
    var currentCharacterLimit: Int {
        settings.currentCharacterLimit
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
        settings.colorSchemeOverride
    }
    
    // MARK: - Style Controls
    
    /// Indicates whether there are active style controls for the current provider
    var hasActiveStyleControls: Bool {
        settings.hasActiveStyleControls
    }

    /// Indicates whether any style control can be reset to its default value
    var canResetStyleControls: Bool {
        settings.canResetStyleControls
    }
    
    // MARK: - Export Format Help
    
    /// Returns help text describing the export format options for the selected provider
    var exportFormatHelpText: String? {
        settings.exportFormatHelpText
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
    
    // MARK: - Cost Estimation
    
    /// Returns the cost estimate for the current input text and provider
    var costEstimate: CostEstimate {
        let profile = ProviderCostProfile.profile(for: settings.selectedProvider)
        return profile.estimate(for: effectiveCharacterCount)
    }

    /// Returns a summary string for the cost estimate
    var costEstimateSummary: String { costEstimate.summary }

    /// Returns additional detail for the cost estimate, if available
    var costEstimateDetail: String? { costEstimate.detail }
    
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
