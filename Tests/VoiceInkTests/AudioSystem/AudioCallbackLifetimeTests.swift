import AudioToolbox
import XCTest
@testable import VoiceInk

final class AudioCallbackLifetimeTests: XCTestCase {
    func testStallWatchdogReportsWithoutReleasingCallbackOwnership() async {
        let gate = AudioCallbackGate()
        gate.open()
        XCTAssertTrue(gate.tryEnter())
        gate.close()
        let reported = expectation(description: "Stall is surfaced")
        let finished = expectation(description: "Drain eventually completes")
        DispatchQueue.global().async {
            gate.waitUntilDrained(stalledAfter: 0.01, onStalledDrain: {
                XCTAssertFalse(gate.isDrained)
                reported.fulfill()
            }, onSlowDrain: {})
            finished.fulfill()
        }
        await fulfillment(of: [reported], timeout: 2)
        XCTAssertFalse(gate.isDrained)
        gate.leave()
        await fulfillment(of: [finished], timeout: 2)
    }

    func testClosedGateRejectsCallbacksAndCannotDrainUntilLastCallbackLeaves() {
        let gate = AudioCallbackGate()
        XCTAssertFalse(gate.tryEnter())
        gate.open()
        XCTAssertTrue(gate.tryEnter())
        XCTAssertTrue(gate.tryEnter())
        gate.close()
        XCTAssertFalse(gate.tryEnter())
        XCTAssertFalse(gate.isDrained)
        gate.leave()
        XCTAssertFalse(gate.isDrained)
        gate.leave()
        XCTAssertTrue(gate.isDrained)
        gate.open()
        XCTAssertTrue(gate.tryEnter())
        gate.close()
        gate.leave()
        XCTAssertTrue(gate.isDrained)
    }

    func testSlowCallbackDoesNotGrantPermissionToRetireResources() async {
        let gate = AudioCallbackGate()
        gate.open()
        XCTAssertTrue(gate.tryEnter())
        gate.close()
        let warned = expectation(description: "Drain diagnostic after 200ms")
        let completed = expectation(description: "Drain completed after callback leaves")
        let prematureCompletion = expectation(description: "Drain must stay pending while callback is held")
        prematureCompletion.isInverted = true
        DispatchQueue.global().async {
            gate.waitUntilDrained { warned.fulfill() }
            if !gate.isDrained { prematureCompletion.fulfill() }
            XCTAssertTrue(gate.isDrained, "A diagnostic timeout must not let the drain return early")
            completed.fulfill()
        }
        await fulfillment(of: [warned], timeout: 2)
        // Keep ownership after the diagnostic so an early return has time to become observable.
        await fulfillment(of: [prematureCompletion], timeout: 0.1)
        XCTAssertFalse(gate.isDrained)
        XCTAssertFalse(gate.tryEnter())
        gate.leave()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertTrue(gate.isDrained)
    }

    func testStopWaitsForFinalPCMThenClosesReadableWAV() async throws {
        let recorder = CoreAudioRecorder()
        recorder.outputFormat = AudioStreamBasicDescription(
            mSampleRate: 16000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer {
            // Best-effort cleanup of a temporary test recording.
            try? FileManager.default.removeItem(at: url)
        }
        try recorder.createOutputFile(at: url)
        try recorder.allocateAudioBuffers(
            maxFrames: 4096, channelCount: 1, inputSampleRate: 16000, resetQueuedAudio: true
        )
        recorder.callbackGate.open()
        XCTAssertTrue(recorder.callbackGate.tryEnter())
        let stopped = expectation(description: "Stop returns only after file close")
        DispatchQueue.global().async {
            recorder.stopRecording()
            stopped.fulfill()
        }
        // Hold a callback beyond the old timeout, then deliver its final audio before leaving.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(recorder.callbackGate.tryEnter())
        let samples = [Int16](repeating: 123, count: 160)
        recorder.audioProcessingQueue.sync {
            samples.withUnsafeBufferPointer { recorder.writeConvertedFrames($0) }
        }
        recorder.callbackGate.leave()
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertNil(recorder.audioFile)
        var file: ExtAudioFileRef?
        XCTAssertEqual(ExtAudioFileOpenURL(url as CFURL, &file), noErr)
        let readableFile = try XCTUnwrap(file)
        defer { ExtAudioFileDispose(readableFile) }
        var frames: Int64 = 0
        var size = UInt32(MemoryLayout<Int64>.size)
        XCTAssertEqual(ExtAudioFileGetProperty(readableFile, kExtAudioFileProperty_FileLengthFrames, &size, &frames), noErr)
        XCTAssertEqual(frames, 160)
    }

    func testConverterSetupFailureIsReported() {
        let recorder = CoreAudioRecorder()
        // An unconfigured output sample rate cannot produce usable audio.
        XCTAssertThrowsError(try recorder.allocateAudioBuffers(
            maxFrames: 4096, channelCount: 1, inputSampleRate: 48000, resetQueuedAudio: true
        ))
    }
}
