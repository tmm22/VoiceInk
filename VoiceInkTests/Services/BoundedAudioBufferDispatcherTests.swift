import AVFoundation
import os
import XCTest
@testable import VoiceInk

final class BoundedAudioBufferDispatcherTests: XCTestCase {
    func testCopiesTapBufferBeforeDeferredProcessing() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let source = try makeBuffer(format: format, samples: [0.25, 0.5, 0.75])
        let gate = DispatchSemaphore(value: 0)
        let processed = expectation(description: "processed")
        let received = OSAllocatedUnfairLock(initialState: [Float]())

        let dispatcher = try XCTUnwrap(BoundedAudioBufferDispatcher(
            format: format,
            frameCapacity: 16,
            processor: { buffer in
                gate.wait()
                let samples = Array(UnsafeBufferPointer(
                    start: buffer.floatChannelData?[0],
                    count: Int(buffer.frameLength)
                ))
                received.withLock { $0 = samples }
                processed.fulfill()
            },
            failureHandler: { _ in }
        ))

        dispatcher.submit(source)
        source.floatChannelData?[0][0] = -1
        gate.signal()
        wait(for: [processed], timeout: 1)
        dispatcher.stopAndDrain()

        XCTAssertEqual(received.withLock { $0 }, [0.25, 0.5, 0.75])
    }

    func testPoolExhaustionReportsOneErrorAndStopsAcceptance() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let source = try makeBuffer(format: format, samples: [0.25])
        let gate = DispatchSemaphore(value: 0)
        let failed = expectation(description: "failed")
        failed.expectedFulfillmentCount = 1
        let failureCount = OSAllocatedUnfairLock(initialState: 0)

        let dispatcher = try XCTUnwrap(BoundedAudioBufferDispatcher(
            format: format,
            frameCapacity: 16,
            poolSize: 1,
            processor: { _ in gate.wait() },
            failureHandler: { _ in
                failureCount.withLock { $0 += 1 }
                failed.fulfill()
            }
        ))

        dispatcher.submit(source)
        dispatcher.submit(source)
        dispatcher.submit(source)
        wait(for: [failed], timeout: 1)
        gate.signal()
        dispatcher.stopAndDrain()

        XCTAssertEqual(failureCount.withLock { $0 }, 1)
    }

    func testReusableSlotAcceptsLongerBufferAfterShortBuffer() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let processed = expectation(description: "processed")
        processed.expectedFulfillmentCount = 2
        let lengths = OSAllocatedUnfairLock(initialState: [Int]())
        let dispatcher = try XCTUnwrap(BoundedAudioBufferDispatcher(
            format: format,
            frameCapacity: 16,
            poolSize: 1,
            processor: { buffer in
                lengths.withLock { $0.append(Int(buffer.frameLength)) }
                processed.fulfill()
            },
            failureHandler: { _ in }
        ))

        dispatcher.submit(try makeBuffer(format: format, samples: [1]))
        dispatcher.drain()
        dispatcher.submit(try makeBuffer(format: format, samples: [1, 2, 3, 4]))
        wait(for: [processed], timeout: 1)
        dispatcher.stopAndDrain()

        XCTAssertEqual(lengths.withLock { $0 }, [1, 4])
    }

    func testProcessorFailureSkipsAlreadyQueuedBuffers() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let gate = DispatchSemaphore(value: 0)
        let failed = expectation(description: "failed")
        let processedCount = OSAllocatedUnfairLock(initialState: 0)
        let dispatcher = try XCTUnwrap(BoundedAudioBufferDispatcher(
            format: format,
            frameCapacity: 16,
            poolSize: 3,
            processor: { _ in
                let count = processedCount.withLock { count -> Int in count += 1; return count }
                if count == 1 {
                    gate.wait()
                    throw AudioEngineRecorderError.bufferConversionFailed
                }
            },
            failureHandler: { _ in failed.fulfill() }
        ))

        let source = try makeBuffer(format: format, samples: [1])
        dispatcher.submit(source)
        dispatcher.submit(source)
        dispatcher.submit(source)
        gate.signal()
        wait(for: [failed], timeout: 1)
        dispatcher.stopAndDrain()

        XCTAssertEqual(processedCount.withLock { $0 }, 1)
    }

    private func makeBuffer(format: AVAudioFormat, samples: [Float]) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else {
            throw CocoaError(.coderInvalidValue)
        }
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }
}
