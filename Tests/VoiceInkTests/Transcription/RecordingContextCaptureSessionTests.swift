import Combine
import XCTest
@testable import VoiceInk

/// Drives `RecordingContextCaptureSession` with a fake capture starter that only notes which kinds
/// were requested, so no pasteboard, Accessibility or screen capture is touched.
@MainActor
final class RecordingContextCaptureSessionTests: XCTestCase {
    private let configurationChanges = PassthroughSubject<[ModeConfig], Never>()
    private var requestedKinds: [RecordingContextCaptureKinds] = []
    private var captureTasks: [Task<Void, Never>] = []
    private var isRecording = true
    private var frontmostProcessID: pid_t? = 100

    private let dictationMode = ModeConfig.contextCaptureTestMode(aiEnhancement: false, provider: nil)
    private let screenMode = ModeConfig.contextCaptureTestMode(screen: true)
    private let selectedTextMode = ModeConfig.contextCaptureTestMode(selectedText: true)

    override func tearDown() async throws {
        captureTasks.forEach { $0.cancel() }
        captureTasks.removeAll()
    }

    // MARK: - Start

    func testStartCapturesOnlyWhatAnEnabledModeCanConsume() {
        let session = makeSession()
        start(session, with: [dictationMode])

        XCTAssertEqual(requestedKinds, [[.clipboard]])
        XCTAssertEqual(session.startedKinds, [.clipboard])
    }

    func testStartCapturesEveryKindInOneRequestWhenAllAreNeeded() {
        let session = makeSession()
        start(session, with: [dictationMode, screenMode, selectedTextMode])

        XCTAssertEqual(requestedKinds, [.all])
        XCTAssertEqual(session.startedKinds, .all)
    }

    func testRecordingThatCannotEnhanceCapturesNothingAndIgnoresModeChanges() {
        let session = makeSession(canEnhance: false)
        start(session, with: [screenMode, selectedTextMode])
        configurationChanges.send([screenMode, selectedTextMode])

        XCTAssertEqual(requestedKinds, [])
        XCTAssertEqual(session.startedKinds, [])
    }

    func testSmartPunctuationKeepsSelectedTextCaptureAtStart() {
        let session = makeSession(smartPunctuation: true)
        start(session, with: [dictationMode])
        XCTAssertEqual(requestedKinds, [[.clipboard, .selectedText]])

        isRecording = false
        configurationChanges.send([selectedTextMode])
        XCTAssertEqual(requestedKinds, [[.clipboard, .selectedText]], "Already captured when the recording started")
    }

    func testSmartPunctuationWithoutEnhancementCapturesOnlySelectedText() {
        let session = makeSession(canEnhance: false, smartPunctuation: true)
        start(session, with: [screenMode])
        configurationChanges.send([screenMode, selectedTextMode])

        XCTAssertEqual(requestedKinds, [[.selectedText]])
        XCTAssertEqual(session.startedKinds, [.selectedText])
    }

    // MARK: - Mode changes while the session is alive

    func testKindThatBecomesNeededIsCapturedOnceIntoTheSameStore() {
        let session = makeSession()
        start(session, with: [dictationMode])

        configurationChanges.send([dictationMode, screenMode])
        XCTAssertEqual(requestedKinds, [[.clipboard], [.screen]])
        XCTAssertEqual(session.store.snapshot.screenText, "captured 4")

        configurationChanges.send([dictationMode, screenMode])
        configurationChanges.send([dictationMode])
        configurationChanges.send([dictationMode, screenMode])
        XCTAssertEqual(requestedKinds, [[.clipboard], [.screen]], "A kind is captured at most once per recording")
    }

    func testModeChangeThatNeedsNothingNewStartsNoCapture() {
        let session = makeSession()
        start(session, with: [screenMode])

        configurationChanges.send([screenMode, dictationMode])
        configurationChanges.send([ModeConfig.contextCaptureTestMode(enabled: false, selectedText: true)])
        configurationChanges.send([ModeConfig.contextCaptureTestMode(aiEnhancement: false, selectedText: true)])

        XCTAssertEqual(requestedKinds, [[.clipboard, .screen]])
        XCTAssertEqual(session.startedKinds, [.clipboard, .screen])
    }

    func testLateSelectedTextWaitsForAnActiveRecordingInTheOriginalApplication() {
        let session = makeSession()
        start(session, with: [dictationMode])

        isRecording = false
        configurationChanges.send([selectedTextMode])
        XCTAssertEqual(requestedKinds, [[.clipboard]], "Not while the result may be pasted")

        isRecording = true
        frontmostProcessID = 200
        configurationChanges.send([selectedTextMode])
        XCTAssertEqual(requestedKinds, [[.clipboard]], "Not from a different application")

        frontmostProcessID = 100
        configurationChanges.send([selectedTextMode])
        XCTAssertEqual(requestedKinds, [[.clipboard], [.selectedText]])
        XCTAssertEqual(session.startedKinds, [.clipboard, .selectedText])
    }

    func testLateScreenCaptureDoesNotDependOnRecordingStateOrFrontmostApplication() {
        let session = makeSession()
        start(session, with: [dictationMode])

        isRecording = false
        frontmostProcessID = 200
        configurationChanges.send([screenMode, selectedTextMode])

        XCTAssertEqual(requestedKinds, [[.clipboard], [.screen]])
        XCTAssertEqual(session.startedKinds, [.clipboard, .screen])
    }

    // MARK: - Cancel

    func testCancelCancelsCapturesAndStopsFollowingModeChanges() {
        let session = makeSession()
        start(session, with: [dictationMode])
        XCTAssertEqual(captureTasks.count, 1)
        XCTAssertFalse(captureTasks[0].isCancelled)

        session.cancel()
        XCTAssertTrue(captureTasks[0].isCancelled)

        configurationChanges.send([screenMode, selectedTextMode])
        XCTAssertEqual(requestedKinds, [[.clipboard]])
    }

    func testReleasingTheSessionCancelsItsCaptures() {
        var session: RecordingContextCaptureSession? = makeSession()
        if let session {
            start(session, with: [dictationMode])
        }
        XCTAssertEqual(captureTasks.count, 1)

        session = nil
        XCTAssertTrue(captureTasks[0].isCancelled)

        configurationChanges.send([screenMode])
        XCTAssertEqual(requestedKinds, [[.clipboard]])
    }

    func testRequestingNoKindsCreatesNoCaptureTasks() {
        let tasks = RecordingContextCaptureService.startCapture(into: RecordingContextSnapshotStore(), kinds: [])
        XCTAssertTrue(tasks.isEmpty)
    }

    // MARK: - Helpers

    private func makeSession(
        canEnhance: Bool = true, smartPunctuation: Bool = false
    ) -> RecordingContextCaptureSession {
        RecordingContextCaptureSession(
            canEnhance: canEnhance,
            pastesWithSmartPunctuation: smartPunctuation,
            isRecording: { [unowned self] in self.isRecording },
            frontmostProcessID: { [unowned self] in self.frontmostProcessID },
            startCapture: { [unowned self] store, kinds in
                self.requestedKinds.append(kinds)
                if kinds.contains(.screen) {
                    store.updateScreenText("captured \(kinds.rawValue)")
                }
                let task = Task<Void, Never> {
                    // Stands in for a capture that is still running; ends as soon as it is cancelled.
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        return
                    }
                }
                self.captureTasks.append(task)
                return [task]
            }
        )
    }

    private func start(_ session: RecordingContextCaptureSession, with configurations: [ModeConfig]) {
        session.start(
            configurations: configurations,
            configurationChanges: configurationChanges.eraseToAnyPublisher()
        )
    }
}
