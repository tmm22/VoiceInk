import XCTest
import Combine
@testable import VoiceInk

extension TTSViewModelTests {
    func testDeinitCancelsAllTasks() async {
        // CRITICAL TEST: TTSViewModel has 5 tasks that must be cancelled in deinit
        var viewModel: TTSViewModel? = makeViewModel()
        weak let weakViewModel = viewModel

        // Set input to trigger potential tasks
        viewModel?.inputText = "Test text for generation"

        // Give time for any tasks to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Release view model - this triggers deinit which should cancel:
        // - batch generation task (owned by TTSSpeechGenerationViewModel)
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
            var vm: TTSViewModel? = makeViewModel()
            vm?.inputText = "Test"

            try? await Task.sleep(nanoseconds: 20_000_000) // 0.02s

            vm = nil

            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        }

        // Give final cleanup time
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // No crash = success
    }

    func testBatchTaskCancellation() async {
        // Test that batch task can be cancelled
        var viewModel: TTSViewModel? = makeViewModel()
        weak let weakVM = viewModel

        // Set batchable text
        viewModel?.inputText = "Text 1\n---\nText 2\n---\nText 3"

        // Release immediately to test cancellation
        viewModel = nil

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(weakVM, "Should deallocate and cancel batch task")
    }

    func testArticleSummaryTaskCancellation() async {
        var viewModel: TTSViewModel? = makeViewModel()
        weak let weakVM = viewModel

        // Try to trigger summarization (may not work without actual setup)
        viewModel?.inputText = "Article content"

        // Release immediately
        viewModel = nil

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(weakVM, "Should cancel article summary task on deinit")
    }

    func testTranscriptionTaskCancellation() async {
        var viewModel: TTSViewModel? = makeViewModel()
        weak let weakVM = viewModel

        // Release while transcription might be pending
        viewModel = nil

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(weakVM, "Should cancel transcription task on deinit")
    }

    func testPublisherSubscriptionsCleanup() async {
        // ViewModel has multiple Combine publishers that must be cancelled
        var viewModel: TTSViewModel? = makeViewModel()
        weak let weakVM = viewModel

        // Subscribe to some publishers
        var receivedValue = false
        viewModel?.playback.$isPlaying
            .sink { _ in receivedValue = true }
            .store(in: &cancellables)
        XCTAssertTrue(receivedValue)

        // Release viewModel
        viewModel = nil
        cancellables.removeAll()

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(weakVM, "Should cleanup publisher subscriptions")
    }

    func testViewModelDoesNotLeak() async {
        weak var weakViewModel: TTSViewModel?

        do {
            let vm = makeViewModel()
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

        do {
            let vm = makeViewModel()
            weakViewModel = vm

            // Subscribe to publishers
            vm.generation.$isGenerating.sink { _ in }.store(in: &localCancellables)
            vm.playback.$isPlaying.sink { _ in }.store(in: &localCancellables)
            vm.playback.$currentTime.sink { _ in }.store(in: &localCancellables)
        }

        localCancellables.removeAll()

        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(weakViewModel, "Should not leak with active subscriptions")
    }

    func testViewModelWithTasksDoesNotLeak() async {
        weak var weakViewModel: TTSViewModel?

        do {
            let vm = makeViewModel()
            weakViewModel = vm

            // Set text to potentially trigger tasks
            vm.inputText = "Text 1\n---\nText 2\n---\nText 3"

            if let voice = vm.availableVoices.first {
                vm.preview.previewVoice(voice)
            }
        }

        // Give time for task cancellation and cleanup
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        XCTAssertNil(weakViewModel, "Should not leak with active tasks")
    }
}
