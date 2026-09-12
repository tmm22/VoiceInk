import XCTest
@testable import VoiceInk

/// Unit tests for Recorder behavior that does not require microphone permission or hardware.
@available(macOS 14.0, *)
@MainActor
final class RecorderTests: XCTestCase {
    private var recorder: Recorder!

    override func setUp() async throws {
        try await super.setUp()
        recorder = Recorder()
    }

    override func tearDown() async throws {
        await recorder.stopRecording()
        recorder = nil
        try await super.tearDown()
    }

    func testStopWithoutStartIsIdempotent() async {
        await recorder.stopRecording()
        await recorder.stopRecording()
        XCTAssertNotNil(recorder)
    }

    func testMeterSnapshotIsSilentWithoutRecorder() {
        let meter = recorder.audioMeterSnapshot()
        XCTAssertEqual(meter, AudioMeter(averagePower: 0, peakPower: 0))
    }

    func testMeterSnapshotStaysNormalized() {
        let meter = recorder.audioMeterSnapshot()
        XCTAssertGreaterThanOrEqual(meter.averagePower, 0)
        XCTAssertLessThanOrEqual(meter.averagePower, 1)
        XCTAssertGreaterThanOrEqual(meter.peakPower, 0)
        XCTAssertLessThanOrEqual(meter.peakPower, 1)
    }

    func testAudioChunkHandlerCanBeReplaced() {
        recorder.onAudioChunk = { _ in }
        XCTAssertNotNil(recorder.onAudioChunk)
        recorder.onAudioChunk = nil
        XCTAssertNil(recorder.onAudioChunk)
    }

    func testRecorderDeallocatesAfterStop() async {
        weak var weakRecorder: Recorder?
        do {
            let temporaryRecorder = Recorder()
            weakRecorder = temporaryRecorder
            await temporaryRecorder.stopRecording()
        }

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(weakRecorder)
    }
}
