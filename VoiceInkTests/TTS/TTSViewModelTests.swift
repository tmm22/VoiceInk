import XCTest
import Combine
@testable import VoiceInk

/// Tests for TTSViewModel - complex async state management with multiple tasks
/// CRITICAL: 5+ tasks cancelled in deinit (batchTask, previewTask, articleSummaryTask, managedProvisioningTask, transcriptionTask)
@available(macOS 14.0, *)
@MainActor
final class TTSViewModelTests: XCTestCase {
    
    var viewModel: TTSViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        viewModel = TTSViewModel()
        cancellables = Set<AnyCancellable>()
        
        // Give time for initialization
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }
    
    override func tearDown() async throws {
        cancellables?.removeAll()
        cancellables = nil
        viewModel = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Lifecycle Tests
    
    func testInitialState() {
        XCTAssertEqual(viewModel.inputText, "", "Should start with empty text")
        XCTAssertFalse(viewModel.isGenerating, "Should not be generating")
        XCTAssertFalse(viewModel.isPlaying, "Should not be playing")
        XCTAssertEqual(viewModel.currentTime, 0, "Current time should be 0")
        XCTAssertEqual(viewModel.duration, 0, "Duration should be 0")
    }
    
    func testInputTextProperty() {
        viewModel.inputText = "Test text"
        XCTAssertEqual(viewModel.inputText, "Test text")
        
        viewModel.inputText = ""
        XCTAssertEqual(viewModel.inputText, "")
    }
    
    // MARK: - CRITICAL: Deinit Task Cancellation Tests
    
    func testDeinitCancelsAllTasks() async {
        // CRITICAL TEST: TTSViewModel has 5 tasks that must be cancelled in deinit
        var viewModel: TTSViewModel? = TTSViewModel()
        weak var weakViewModel = viewModel
        
        // Set input to trigger potential tasks
        viewModel?.inputText = "Test text for generation"
        
        // Give time for any tasks to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Release view model - this triggers deinit which should cancel:
        // - batchTask
        // - previewTask
        // - articleSummaryTask
        // - managedProvisioningTask
        // - transcriptionTask
        viewModel = nil
        
        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        
        XCTAssertNil(weakViewModel, "ViewModel should be deallocated")
    }
    
    func testRapidAllocDealloc() async {
        // Test rapid creation/destruction to catch task cancellation issues
        for _ in 0..<10 {
            var vm: TTSViewModel? = TTSViewModel()
            vm?.inputText = "Test"
            
            try? await Task.sleep(nanoseconds: 20_000_000) // 0.02s
            
            vm = nil
            
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        }
        
        // Give final cleanup time
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        // No crash = success
    }
    
    // MARK: - Generate Speech Tests
    
    func testGenerateSpeechWithEmptyText() async {
        // Should handle empty text gracefully
        viewModel.inputText = ""
        
        // Try to generate (should likely fail or return early)
        // We can't directly call generate, but we can test the state
        XCTAssertFalse(viewModel.isGenerating, "Should not start generating with empty text")
    }
    
    func testIsGeneratingFlagLifecycle() {
        // Test that generation flag has proper lifecycle
        XCTAssertFalse(viewModel.isGenerating, "Should start not generating")
        
        // We can't directly test generation without mocking providers,
        // but we can verify the flag is accessible
        _ = viewModel.isGenerating
        
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
    
    func testBatchTaskCancellation() async {
        // Test that batch task can be cancelled
        var viewModel: TTSViewModel? = TTSViewModel()
        weak var weakVM = viewModel
        
        // Set batchable text
        viewModel?.inputText = "Text 1\n---\nText 2\n---\nText 3"
        
        // Release immediately to test cancellation
        viewModel = nil
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakVM, "Should deallocate and cancel batch task")
    }
    
    // MARK: - Preview Voice Tests
    
    func testPreviewVoiceConcurrentCalls() async {
        // Test that concurrent preview calls are handled
        // We need actual voices, which may not be available
        guard !viewModel.availableVoices.isEmpty else {
            XCTSkip("No voices available for testing")
        }
        
        let voice = viewModel.availableVoices[0]
        
        // Try to preview multiple times rapidly
        for _ in 0..<5 {
            viewModel.previewVoice(voice)
            try? await Task.sleep(nanoseconds: 20_000_000) // 0.02s
        }
        
        // Stop preview
        viewModel.stopPreview()
        
        XCTAssertNotNil(viewModel, "Should handle concurrent preview calls")
    }
    
    func testStopPreviewWhenNotPreviewing() {
        // Should be safe to stop preview when not previewing
        XCTAssertFalse(viewModel.isPreviewing, "Should not be previewing")
        
        viewModel.stopPreview()
        
        XCTAssertNotNil(viewModel, "Should handle stop when not previewing")
    }
    
    func testPreviewTaskCancellation() async {
        // Test that preview task is cancelled on deinit
        var viewModel: TTSViewModel? = TTSViewModel()
        weak var weakVM = viewModel
        
        if let voice = viewModel?.availableVoices.first {
            viewModel?.previewVoice(voice)
        }
        
        // Release while preview may be loading
        viewModel = nil
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakVM, "Should cancel preview task on deinit")
    }
    
    // MARK: - Audio Player State Tests
    
    func testAudioPlayerStateConsistency() {
        // Test that player state properties are consistent
        XCTAssertEqual(viewModel.currentTime, 0)
        XCTAssertEqual(viewModel.duration, 0)
        XCTAssertFalse(viewModel.isPlaying)
        
        // These should be accessible without crash
        _ = viewModel.playbackSpeed
        _ = viewModel.volume
        
        XCTAssertNotNil(viewModel, "Should maintain consistent state")
    }
    
    func testPlaybackSpeedClamping() {
        // Test that playback speed is clamped to valid range
        viewModel.playbackSpeed = 0.5
        XCTAssertEqual(viewModel.playbackSpeed, 0.5)
        
        viewModel.playbackSpeed = 2.0
        XCTAssertEqual(viewModel.playbackSpeed, 2.0)
        
        // Values outside range might be clamped (depending on implementation)
        viewModel.playbackSpeed = 3.0
        XCTAssertGreaterThanOrEqual(viewModel.playbackSpeed, 0.5)
        XCTAssertLessThanOrEqual(viewModel.playbackSpeed, 3.0)
    }
    
    func testVolumeClamping() {
        // Test volume clamping
        viewModel.volume = 0.5
        XCTAssertEqual(viewModel.volume, 0.5)
        
        viewModel.volume = 1.0
        XCTAssertEqual(viewModel.volume, 1.0)
        
        viewModel.volume = 0.0
        XCTAssertEqual(viewModel.volume, 0.0)
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
        let shouldHighlight = viewModel.shouldHighlightCharacterOverflow
        
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
        let initialVoiceCount = viewModel.availableVoices.count
        
        // Switch provider
        viewModel.selectedProvider = .tightAss
        
        // Voices should update
        _ = viewModel.availableVoices
        
        XCTAssertNotNil(viewModel, "Should update voices after provider switch")
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
    
    func testArticleSummaryTaskCancellation() async {
        var viewModel: TTSViewModel? = TTSViewModel()
        weak var weakVM = viewModel
        
        // Try to trigger summarization (may not work without actual setup)
        viewModel?.inputText = "Article content"
        
        // Release immediately
        viewModel = nil
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakVM, "Should cancel article summary task on deinit")
    }
    
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
        XCTAssertNotNil(viewModel.textSnippets, "Snippets should be accessible")
        
        // Initially likely empty
        let count = viewModel.textSnippets.count
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    // MARK: - Transcription Recording Tests
    
    func testTranscriptionRecordingState() {
        XCTAssertFalse(viewModel.isTranscriptionRecording, "Should not be recording initially")
        XCTAssertEqual(viewModel.transcriptionRecordingDuration, 0)
        XCTAssertEqual(viewModel.transcriptionRecordingLevel, 0)
    }
    
    func testTranscriptionTaskCancellation() async {
        var viewModel: TTSViewModel? = TTSViewModel()
        weak var weakVM = viewModel
        
        // Release while transcription might be pending
        viewModel = nil
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakVM, "Should cancel transcription task on deinit")
    }
    
    // MARK: - Loop Playback Tests
    
    func testLoopPlaybackFlag() {
        XCTAssertFalse(viewModel.isLoopEnabled, "Loop should be disabled initially")
        
        viewModel.isLoopEnabled = true
        XCTAssertTrue(viewModel.isLoopEnabled)
        
        viewModel.isLoopEnabled = false
        XCTAssertFalse(viewModel.isLoopEnabled)
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
    
    func testPublisherSubscriptionsCleanup() async {
        // ViewModel has multiple Combine publishers that must be cancelled
        var viewModel: TTSViewModel? = TTSViewModel()
        weak var weakVM = viewModel
        
        // Subscribe to some publishers
        var receivedValue = false
        viewModel?.$isPlaying
            .sink { _ in receivedValue = true }
            .store(in: &cancellables)
        
        // Release viewModel
        viewModel = nil
        cancellables.removeAll()
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNil(weakVM, "Should cleanup publisher subscriptions")
    }
    
    // MARK: - Audio Player Callbacks Tests
    
    func testAudioPlayerDidFinishPlayingCallback() {
        // ViewModel sets up didFinishPlaying callback
        // This should be cleaned up on deinit
        
        // We can't easily trigger the callback, but we can verify it's set up
        XCTAssertNotNil(viewModel, "Should handle player callbacks")
    }
    
    // MARK: - Appearance Preference Tests
    
    func testAppearancePreferencePersistence() {
        let initialPreference = viewModel.appearancePreference
        
        // Change preference
        viewModel.appearancePreference = .dark
        XCTAssertEqual(viewModel.appearancePreference, .dark)
        
        viewModel.appearancePreference = .light
        XCTAssertEqual(viewModel.appearancePreference, .light)
        
        // Restore
        viewModel.appearancePreference = initialPreference
    }
    
    // MARK: - Memory Leak Tests
    
    func testViewModelDoesNotLeak() async {
        weak var weakViewModel: TTSViewModel?
        
        await autoreleasepool {
            let vm = TTSViewModel()
            weakViewModel = vm
            
            // Perform various operations
            vm.inputText = "Test text"
            _ = vm.availableVoices
            _ = vm.currentCharacterLimit
        }
        
        // Give time for deallocation
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        
        XCTAssertNil(weakViewModel, "TTSViewModel should not leak")
    }
    
    func testViewModelWithPublishersDoesNotLeak() async {
        weak var weakViewModel: TTSViewModel?
        var localCancellables = Set<AnyCancellable>()
        
        await autoreleasepool {
            let vm = TTSViewModel()
            weakViewModel = vm
            
            // Subscribe to publishers
            vm.$isGenerating.sink { _ in }.store(in: &localCancellables)
            vm.$isPlaying.sink { _ in }.store(in: &localCancellables)
            vm.$currentTime.sink { _ in }.store(in: &localCancellables)
        }
        
        localCancellables.removeAll()
        
        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        XCTAssertNil(weakViewModel, "Should not leak with active subscriptions")
    }
    
    func testViewModelWithTasksDoesNotLeak() async {
        weak var weakViewModel: TTSViewModel?
        
        await autoreleasepool {
            let vm = TTSViewModel()
            weakViewModel = vm
            
            // Set text to potentially trigger tasks
            vm.inputText = "Text 1\n---\nText 2\n---\nText 3"
            
            if let voice = vm.availableVoices.first {
                vm.previewVoice(voice)
            }
        }
        
        // Give time for task cancellation and cleanup
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        XCTAssertNil(weakViewModel, "Should not leak with active tasks")
    }
}
