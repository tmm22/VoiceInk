import XCTest
@testable import VoiceInk

final class RecordingAudioContinuityTests: XCTestCase {
    func testOutputDurationAcrossDeviceRatesAndCallbackSizes() throws {
        for rate in [8_000.0, 16_000, 22_050, 44_100, 48_000, 96_000] {
            for chunkSize: UInt32 in [32, 128, 512, 4_096] {
                let converter = try makeConverter(rate: rate, chunkSize: chunkSize)
                let samples = (0..<Int(rate)).map { Float(sin(2 * .pi * 440 * Double($0) / rate)) }
                let output = try convert(samples, using: converter, chunkSize: chunkSize)
                XCTAssertEqual(output.count, 16_000, "rate \(rate), chunk size \(chunkSize)")
            }
        }
    }

    func testFlushAndReuseDoNotLeakPreviousUtterance() throws {
        let converter = try makeConverter(rate: 48_000, chunkSize: 128)
        let first = try convert([Float](repeating: 0.4, count: 4_800), using: converter, chunkSize: 128)
        XCTAssertTrue(first.contains { $0 != 0 })
        let second = try convert([Float](repeating: 0, count: 4_800), using: converter, chunkSize: 128)
        XCTAssertEqual(second.count, 1_600)
        XCTAssertTrue(second.allSatisfy { $0 == 0 }, "The next recording must not contain the previous speaker's audio")
    }

    func testShortUtteranceTailIsPreservedAtStop() throws {
        for frames in [1, 17, 127, 511] {
            let converter = try makeConverter(rate: 48_000, chunkSize: 512)
            let output = try convert([Float](repeating: 0.4, count: frames), using: converter, chunkSize: 512)
            XCTAssertEqual(Double(output.count), Double(frames) / 3, accuracy: 1)
        }
    }

    private func makeConverter(rate: Double, chunkSize: UInt32) throws -> RecordingAudioFormatConverter {
        try XCTUnwrap(RecordingAudioFormatConverter(
            inputSampleRate: rate, inputChannelCount: 1, outputSampleRate: 16_000, maxInputFrames: chunkSize
        ))
    }

    private func convert(
        _ input: [Float], using converter: RecordingAudioFormatConverter, chunkSize: UInt32
    ) throws -> [Int16] {
        var result: [Int16] = []
        try input.withUnsafeBufferPointer { samples in
            let base = try XCTUnwrap(samples.baseAddress)
            for offset in stride(from: 0, to: samples.count, by: Int(chunkSize)) {
                let chunk = try XCTUnwrap(converter.convert(
                    interleavedInput: base + offset,
                    frameCount: UInt32(min(Int(chunkSize), samples.count - offset)), channelCount: 1
                ))
                result.append(contentsOf: chunk)
            }
        }
        result.append(contentsOf: try XCTUnwrap(converter.flush()))
        return result
    }
}
