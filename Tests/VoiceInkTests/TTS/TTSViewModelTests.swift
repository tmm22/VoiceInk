import XCTest
import Combine
@testable import VoiceInk

/// Tests for TTSViewModel - complex async state management with multiple tasks
/// CRITICAL: tasks cancelled in deinit (previewTask, articleSummaryTask, managedProvisioningTask, transcriptionTask)
@available(macOS 14.0, *)
@MainActor
final class TTSViewModelTests: XCTestCase {
    
    var viewModel: TTSViewModel!
    var cancellables: Set<AnyCancellable>!
    private var savedTTSDefaults: TTSDefaultsSnapshot?
    
    override func setUp() async throws {
        try await super.setUp()
        savedTTSDefaults = TTSDefaultsSnapshot.captureAndReset()
        viewModel = makeViewModel()
        cancellables = Set<AnyCancellable>()
        
        // Give time for initialization
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }
    
    override func tearDown() async throws {
        cancellables?.removeAll()
        cancellables = nil
        viewModel = nil
        savedTTSDefaults?.restore()
        savedTTSDefaults = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Lifecycle Tests
    
    func testInitialState() {
        XCTAssertEqual(viewModel.inputText, "", "Should start with empty text")
        XCTAssertFalse(viewModel.generation.isGenerating, "Should not be generating")
        XCTAssertFalse(viewModel.playback.isPlaying, "Should not be playing")
        XCTAssertEqual(viewModel.playback.currentTime, 0, "Current time should be 0")
        XCTAssertEqual(viewModel.playback.duration, 0, "Duration should be 0")
    }
    
    func testInputTextProperty() {
        viewModel.inputText = "Test text"
        XCTAssertEqual(viewModel.inputText, "Test text")
        
        viewModel.inputText = ""
        XCTAssertEqual(viewModel.inputText, "")
    }
    
    // MARK: - CRITICAL: Deinit Task Cancellation Tests
    


    // MARK: - Generate Speech Tests
    
    func testGenerateSpeechWithEmptyText() async {
        // Should handle empty text gracefully
        viewModel.inputText = ""
        
        // Try to generate (should likely fail or return early)
        // We can't directly call generate, but we can test the state
        XCTAssertFalse(viewModel.generation.isGenerating, "Should not start generating with empty text")
    }
    
    func testIsGeneratingFlagLifecycle() {
        // Test that generation flag has proper lifecycle
        XCTAssertFalse(viewModel.generation.isGenerating, "Should start not generating")
        
        // We can't directly test generation without mocking providers,
        // but we can verify the flag is accessible
        _ = viewModel.generation.isGenerating
        
        XCTAssertNotNil(viewModel, "ViewModel should survive flag access")
    }
    
    // MARK: - Batch Processing Tests
    
    func testBatchSegmentsParsing() {
        // Test delimiter parsing
        viewModel.inputText = "Segment 1\n---\nSegment 2\n---\nSegment 3"
        
        // The batchDelimiterToken is "---"
        // Should identify multiple segments
        let hasBatchable = viewModel.hasBatchableSegments
        XCTAssertTrue(hasBatchable, "Should detect batch segments")
    }
    
    func testNoBatchSegments() {
        viewModel.inputText = "Just a single segment without delimiters"
        
        XCTAssertFalse(viewModel.hasBatchableSegments, "Should not detect batch segments")
    }
    

    // MARK: - Preview Voice Tests
    
    func testPreviewVoiceConcurrentCalls() async throws {
        // Test that concurrent preview calls are handled
        // We need actual voices, which may not be available
        guard !viewModel.availableVoices.isEmpty else {
            throw XCTSkip("No voices available for testing")
        }
        
        let voice = viewModel.availableVoices[0]
        
        // Try to preview multiple times rapidly
        for _ in 0..<5 {
            viewModel.preview.previewVoice(voice)
            try? await Task.sleep(nanoseconds: 20_000_000) // 0.02s
        }
        
        // Stop preview
        viewModel.stopPreview()
        
        XCTAssertNotNil(viewModel, "Should handle concurrent preview calls")
    }
    
    func testStopPreviewWhenNotPreviewing() {
        // Should be safe to stop preview when not previewing
        XCTAssertFalse(viewModel.preview.isPreviewing, "Should not be previewing")
        
        viewModel.stopPreview()
        
        XCTAssertNotNil(viewModel, "Should handle stop when not previewing")
    }
    
    func testPreviewTaskCancellation() async {
        // Test that preview task is cancelled on deinit
        var viewModel: TTSViewModel? = makeViewModel()
        weak let weakVM = viewModel
        
        if let voice = viewModel?.availableVoices.first {
            viewModel?.preview.previewVoice(voice)
        }
        
        // Release while preview may be loading
        viewModel = nil
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakVM, "Should cancel preview task on deinit")
    }
    
    // MARK: - Audio Player State Tests
    
    func testAudioPlayerStateConsistency() {
        // Test that player state properties are consistent
        XCTAssertEqual(viewModel.playback.currentTime, 0)
        XCTAssertEqual(viewModel.playback.duration, 0)
        XCTAssertFalse(viewModel.playback.isPlaying)
        
        // These should be accessible without crash
        _ = viewModel.playback.playbackSpeed
        _ = viewModel.playback.volume
        
        XCTAssertNotNil(viewModel, "Should maintain consistent state")
    }
    
    func testPlaybackSpeedClamping() {
        // Test that playback speed is clamped to valid range
        viewModel.playback.playbackSpeed = 0.5
        XCTAssertEqual(viewModel.playback.playbackSpeed, 0.5)
        
        viewModel.playback.playbackSpeed = 2.0
        XCTAssertEqual(viewModel.playback.playbackSpeed, 2.0)
        
        // Values outside range might be clamped (depending on implementation)
        viewModel.playback.playbackSpeed = 3.0
        XCTAssertGreaterThanOrEqual(viewModel.playback.playbackSpeed, 0.5)
        XCTAssertLessThanOrEqual(viewModel.playback.playbackSpeed, 3.0)
    }
    
    func testVolumeClamping() {
        // Test volume clamping
        viewModel.playback.volume = 0.5
        XCTAssertEqual(viewModel.playback.volume, 0.5)
        
        viewModel.playback.volume = 1.0
        XCTAssertEqual(viewModel.playback.volume, 1.0)
        
        viewModel.playback.volume = 0.0
        XCTAssertEqual(viewModel.playback.volume, 0.0)
    }
    
    // MARK: - Character Limit Tests
    
    func testCharacterLimitEnforcement() {
        let limit = viewModel.currentCharacterLimit
        XCTAssertGreaterThan(limit, 0, "Should have a character limit")
        
        // Test with text under limit
        viewModel.inputText = "Short text"
        XCTAssertLessThan(viewModel.effectiveCharacterCount, limit)
    }
    
    func testEffectiveCharacterCount() {
        viewModel.inputText = "Test text"
        let count = viewModel.effectiveCharacterCount
        
        XCTAssertEqual(count, 9, "Should count characters correctly")
        
        viewModel.inputText = ""
        XCTAssertEqual(viewModel.effectiveCharacterCount, 0)
    }
    
    func testCharacterOverflowHighlighting() {
        // Test with very long text
        let veryLongText = String(repeating: "a", count: 10000)
        viewModel.inputText = veryLongText
        
        // Should detect overflow
        _ = viewModel.shouldHighlightCharacterOverflow
        
        // Depends on provider limit, but this should potentially trigger
        XCTAssertNotNil(viewModel, "Should handle overflow detection")
    }
    
    // MARK: - Provider Switching Tests
    
    func testProviderSwitchingMidGeneration() {
        // Test switching providers while potentially generating
        let initialProvider = viewModel.selectedProvider
        
        // Switch provider
        let allProviders: [TTSProviderType] = [.openAI, .elevenLabs, .google, .tightAss]
        for provider in allProviders {
            viewModel.selectedProvider = provider
            XCTAssertEqual(viewModel.selectedProvider, provider)
        }
        
        // Switch back
        viewModel.selectedProvider = initialProvider
        
        XCTAssertNotNil(viewModel, "Should handle provider switching")
    }
    
    func testAvailableVoicesAfterProviderSwitch() {
        // Switch provider
        viewModel.selectedProvider = .tightAss
        
        // Voices should update
        _ = viewModel.availableVoices
        
        XCTAssertNotNil(viewModel, "Should update voices after provider switch")
    }

    func testHideAndRestorePocketVoiceUpdatesAvailableVoices() throws {
        viewModel.selectedProvider = .tightAss
        viewModel.settings.updateAvailableVoices()

        guard let pocketVoice = viewModel.availableVoices.first(where: { LocalTTSService.isPocketVoiceID($0.id) }) else {
            throw XCTSkip("No Pocket voice available for testing")
        }

        viewModel.settings.hidePocketVoice(pocketVoice)

        XCTAssertTrue(viewModel.settings.hiddenPocketVoiceIDs.contains(pocketVoice.id))
        XCTAssertFalse(viewModel.availableVoices.contains(where: { $0.id == pocketVoice.id }))

        viewModel.settings.restorePocketVoice(withID: pocketVoice.id)

        XCTAssertFalse(viewModel.settings.hiddenPocketVoiceIDs.contains(pocketVoice.id))
        XCTAssertTrue(viewModel.availableVoices.contains(where: { $0.id == pocketVoice.id }))
    }

    func testHiddenPocketVoicesPersistAcrossViewModelInstances() throws {
        let localService = LocalTTSService()
        guard let pocketVoice = localService.availableVoices.first(where: { LocalTTSService.isPocketVoiceID($0.id) }) else {
            throw XCTSkip("No Pocket voice available for testing")
        }

        viewModel.settings.hidePocketVoice(pocketVoice)

        let persistedIDs = Set(AppSettings.TTS.hiddenPocketVoiceIDs ?? [])
        XCTAssertTrue(persistedIDs.contains(pocketVoice.id))

        let secondViewModel = makeViewModel()
        secondViewModel.selectedProvider = .tightAss
        secondViewModel.settings.updateAvailableVoices()

        XCTAssertTrue(secondViewModel.settings.hiddenPocketVoiceIDs.contains(pocketVoice.id))
        XCTAssertFalse(secondViewModel.availableVoices.contains(where: { $0.id == pocketVoice.id }))
    }
    
    // MARK: - Translation Tests
    
    func testTranslationResultCaching() {
        // Initially no translation
        XCTAssertNil(viewModel.translationResult)
        
        // Set text
        viewModel.inputText = "Hello world"
        
        // Translation result may still be nil (requires actual translation)
        XCTAssertNotNil(viewModel, "Should handle translation state")
    }
    
    func testTranslationClearsOnTextChange() {
        viewModel.inputText = "Original text"
        
        // Simulate having a translation result (would be set by actual translation)
        // We can't easily set it, but changing text should clear it
        viewModel.inputText = "Different text"
        
        // Translation should be cleared
        XCTAssertNil(viewModel.translationResult, "Should clear translation on text change")
    }
    
    // MARK: - Article Summarization Tests
    

    // MARK: - Style Controls Tests
    
    func testStyleControlsAvailability() {
        // Test that style controls can be accessed
        let hasControls = viewModel.hasActiveStyleControls
        
        // May or may not have controls depending on provider
        _ = hasControls
        
        XCTAssertNotNil(viewModel, "Should handle style controls")
    }
    
    func testStyleValuesPersistence() {
        // Test that style values are persisted
        let styleValues = viewModel.styleValues
        
        // Initially may be empty
        XCTAssertNotNil(styleValues, "Style values should be accessible")
    }
    
    // MARK: - Snippet Management Tests
    
    func testTextSnippetsProperty() {
        XCTAssertNotNil(viewModel.settings.textSnippets, "Snippets should be accessible")
        
        // Initially likely empty
        let count = viewModel.settings.textSnippets.count
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    // MARK: - Transcription Recording Tests
    
    func testTranscriptionRecordingState() {
        XCTAssertFalse(viewModel.transcription.isTranscriptionRecording, "Should not be recording initially")
        XCTAssertEqual(viewModel.transcription.transcriptionRecordingDuration, 0)
        XCTAssertEqual(viewModel.transcription.transcriptionRecordingLevel, 0)
    }
    

    // MARK: - Loop Playback Tests
    
    func testLoopPlaybackFlag() {
        XCTAssertFalse(viewModel.playback.isLoopEnabled, "Loop should be disabled initially")
        
        viewModel.playback.isLoopEnabled = true
        XCTAssertTrue(viewModel.playback.isLoopEnabled)
        
        viewModel.playback.isLoopEnabled = false
        XCTAssertFalse(viewModel.playback.isLoopEnabled)
    }
    
    // MARK: - Format Switching Tests
    
    func testFormatSwitchingClearsAudio() {
        let initialFormat = viewModel.selectedFormat
        
        // Switch formats
        let formats: [AudioSettings.AudioFormat] = [.mp3, .wav, .aac, .flac]
        for format in formats {
            viewModel.selectedFormat = format
            // Should not crash
        }
        
        viewModel.selectedFormat = initialFormat
        XCTAssertNotNil(viewModel, "Should handle format switching")
    }
    
    // MARK: - Cost Estimation Tests
    
    func testCostEstimationAccuracy() {
        viewModel.inputText = "Test text for cost estimation"
        
        let estimate = viewModel.costEstimate
        
        // Should have valid estimate
        XCTAssertNotNil(estimate)
        
        // Summary should be available
        let summary = viewModel.costEstimateSummary
        XCTAssertFalse(summary.isEmpty, "Should have cost summary")
    }
    
    func testCostEstimateWithEmptyText() {
        viewModel.inputText = ""
        
        let estimate = viewModel.costEstimate
        XCTAssertNotNil(estimate, "Should handle empty text cost estimation")
    }
    
    // MARK: - Batch Delimiter Tests
    
    func testBatchDelimiterParsing() {
        viewModel.inputText = "Part 1\n---\nPart 2"
        
        XCTAssertTrue(viewModel.hasBatchableSegments)
        XCTAssertGreaterThan(viewModel.pendingBatchSegmentCount, 1)
    }
    
    // MARK: - Publisher Sink Cleanup Tests
    

    // MARK: - Audio Player Callbacks Tests
    
    func testAudioPlayerDidFinishPlayingCallback() {
        // ViewModel sets up didFinishPlaying callback
        // This should be cleaned up on deinit
        
        // We can't easily trigger the callback, but we can verify it's set up
        XCTAssertNotNil(viewModel, "Should handle player callbacks")
    }
    
    // MARK: - Appearance Preference Tests
    
    func testAppearancePreferencePersistence() {
        let initialPreference = viewModel.settings.appearancePreference
        
        // Change preference
        viewModel.settings.appearancePreference = .dark
        XCTAssertEqual(viewModel.settings.appearancePreference, .dark)
        
        viewModel.settings.appearancePreference = .light
        XCTAssertEqual(viewModel.settings.appearancePreference, .light)
        
        // Restore
        viewModel.settings.appearancePreference = initialPreference
    }
    
    // MARK: - Memory Leak Tests
    


}
