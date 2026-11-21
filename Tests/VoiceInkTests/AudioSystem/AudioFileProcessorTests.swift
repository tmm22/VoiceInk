import AVFoundation
import XCTest
@testable import VoiceInk

/// Pins the bytes produced by audio-file import: the peak normalisation and the 16-bit WAV export
/// must stay identical to the whole-array implementation they replaced.
final class AudioFileProcessorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileSystemHelper.createIsolatedDirectory(prefix: "AudioFileProcessor")
    }

    override func tearDownWithError() throws {
        FileSystemHelper.cleanupDirectory(directory)
    }

    // MARK: - Reference implementations (the code that was replaced)

    private func referenceNormalization(_ input: [Float]) -> [Float] {
        var samples = input
        let maxSample = samples.map(abs).max() ?? 1
        if maxSample > 0 {
            samples = samples.map { $0 / maxSample }
        }
        return samples
    }

    private func referenceInt16Samples(_ samples: [Float]) -> [Int16] {
        samples.map { max(-1.0, min(1.0, $0)) * Float(Int16.max) }.map { Int16($0) }
    }

    /// The export as it was before it became block-based: one full-length buffer, one write.
    private func writeWithSingleBuffer(_ samples: [Float], to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        // A zero-capacity buffer has no channel storage; an empty export writes a zero-frame buffer.
        if !samples.isEmpty {
            let channel = try XCTUnwrap(buffer.int16ChannelData?[0])
            for (index, sample) in referenceInt16Samples(samples).enumerated() {
                channel[index] = sample
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        try file.write(from: buffer)
    }

    // MARK: - Helpers

    private func randomSamples(count: Int, seed: UInt64, range: ClosedRange<Float> = -1.25...1.25) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in Float.random(in: range, using: &generator) }
    }

    private func bitPatterns(_ samples: [Float]) -> [UInt32] {
        samples.map(\.bitPattern)
    }

    private func littleEndianBytes(_ samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Returns the payload of the WAV `data` chunk. Writers pad before it, so it is not at byte 44.
    private func dataChunkPayload(of url: URL) throws -> Data {
        let file = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: file.prefix(4), as: UTF8.self), "RIFF")

        var offset = 12
        while offset + 8 <= file.count {
            let identifier = String(decoding: file[offset..<offset + 4], as: UTF8.self)
            let size = file[offset + 4..<offset + 8].enumerated().reduce(0) { partial, byte in
                partial | Int(byte.element) << (8 * byte.offset)
            }
            let payloadStart = offset + 8
            if identifier == "data" {
                return file.subdata(in: payloadStart..<min(payloadStart + size, file.count))
            }
            offset = payloadStart + size + (size & 1)
        }
        throw MissingDataChunk()
    }

    private struct MissingDataChunk: Error {}

    // MARK: - Peak normalisation

    func testPeakNormalizationMatchesReplacedExpressionBitForBit() {
        var cases: [[Float]] = [
            [],
            [0], [-0.0], [0, -0.0, 0],
            [1], [-1], [0.25, -0.75, 0.75], [-3, 2, 1],
            [.nan], [.nan, 0.5, -2], [0.5, .nan, -2], [0.5, -2, .nan], [-.nan, 1],
            [.infinity, 1, -1], [1, -.infinity, 3],
            [.leastNonzeroMagnitude, -.leastNonzeroMagnitude],
            [.greatestFiniteMagnitude, 1e-30, -3],
        ]
        for (count, seed) in [(1, 1), (2, 2), (17, 3), (1_000, 4), (65_537, 5)] {
            cases.append(randomSamples(count: count, seed: UInt64(seed), range: -3...3))
        }
        // Arbitrary bit patterns: subnormals, infinities and NaN payloads in every position.
        var generator = SeededGenerator(seed: 99)
        for count in [3, 64, 4_099] {
            cases.append((0..<count).map { _ in Float(bitPattern: UInt32.random(in: .min ... .max, using: &generator)) })
        }

        for (index, input) in cases.enumerated() {
            var actual = input
            AudioProcessor.normalizeToPeak(&actual)

            XCTAssertEqual(
                bitPatterns(actual), bitPatterns(referenceNormalization(input)),
                "case \(index) with \(input.count) samples"
            )
        }
    }

    func testPeakNormalizationScalesLargestMagnitudeToOne() {
        var samples: [Float] = [0.25, -0.5, 0.125]
        AudioProcessor.normalizeToPeak(&samples)

        XCTAssertEqual(samples, [0.5, -1, 0.25])
    }

    func testSilenceIsLeftUntouchedByPeakNormalization() {
        var samples: [Float] = [0, 0, 0]
        AudioProcessor.normalizeToPeak(&samples)

        XCTAssertEqual(samples, [0, 0, 0])
    }

    // MARK: - WAV export

    func testWavExportWritesClampedScaledTruncatedSamples() throws {
        let samples: [Float] = [
            0, 1, -1, 0.5, -0.5, 2, -2, 0.99999, 1e-9, -0.0, .nan, .infinity, -.infinity, 0.25, -0.75,
        ]
        let expected: [Int16] = [
            0, 32_767, -32_767, 16_383, -16_383, 32_767, -32_767, 32_766, 0, 0, 32_767, 32_767, -32_767, 8_191, -24_575,
        ]
        XCTAssertEqual(referenceInt16Samples(samples), expected, "Precondition: the reference arithmetic")

        let url = directory.appendingPathComponent("pinned.wav")
        try AudioProcessor.writeSamplesAsWav(samples: samples, to: url, framesPerBlock: 4)

        XCTAssertEqual(try dataChunkPayload(of: url), littleEndianBytes(expected))
    }

    func testWavExportIsByteIdenticalToSingleBufferExportForEveryBlockSize() throws {
        var samples = randomSamples(count: 10_007, seed: 7)
        samples[0] = .nan
        samples[1] = .infinity
        samples[2] = -.infinity
        samples[3] = 1
        samples[4] = -1

        let referenceURL = directory.appendingPathComponent("reference.wav")
        try writeWithSingleBuffer(samples, to: referenceURL)
        let reference = try Data(contentsOf: referenceURL)
        XCTAssertEqual(try dataChunkPayload(of: referenceURL), littleEndianBytes(referenceInt16Samples(samples)))

        let blockSizes = [1, 7, 4_096, samples.count - 1, samples.count, samples.count + 1, Int.max, 0, -3]
        for blockSize in blockSizes {
            let url = directory.appendingPathComponent("blocks-\(blockSize).wav")
            try AudioProcessor.writeSamplesAsWav(samples: samples, to: url, framesPerBlock: blockSize)

            XCTAssertEqual(try Data(contentsOf: url), reference, "framesPerBlock=\(blockSize)")
        }
    }

    func testWavExportCrossesTheProductionBlockBoundaryUnchanged() throws {
        // A repeating period keeps this quick while still spilling into a second production-sized block.
        let period = randomSamples(count: 4_099, seed: 11)
        let count = AudioProcessor.wavExportBlockFrames + 5
        var samples: [Float] = []
        samples.reserveCapacity(count)
        while samples.count < count {
            samples.append(contentsOf: period.prefix(count - samples.count))
        }

        let url = directory.appendingPathComponent("long.wav")
        try AudioProcessor.writeSamplesAsWav(
            samples: samples, to: url, framesPerBlock: AudioProcessor.wavExportBlockFrames)

        let periodBytes = littleEndianBytes(referenceInt16Samples(period))
        let expectedByteCount = count * MemoryLayout<Int16>.size
        var expected = Data(capacity: expectedByteCount)
        while expected.count < expectedByteCount {
            expected.append(periodBytes.prefix(expectedByteCount - expected.count))
        }
        let payload = try dataChunkPayload(of: url)
        XCTAssertEqual(payload.count, expected.count)
        XCTAssertTrue(payload == expected, "The exported samples differ from the per-sample reference")
    }

    func testEmptyRecordingStillExportsAnEmptyWav() throws {
        let referenceURL = directory.appendingPathComponent("reference-empty.wav")
        try writeWithSingleBuffer([], to: referenceURL)

        let url = directory.appendingPathComponent("empty.wav")
        try AudioProcessor.writeSamplesAsWav(samples: [], to: url, framesPerBlock: 1_024)

        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: referenceURL))
        XCTAssertEqual(try dataChunkPayload(of: url).count, 0)
    }

    func testAsyncExportMatchesBlockExport() async throws {
        let samples = randomSamples(count: 3_001, seed: 13)
        let referenceURL = directory.appendingPathComponent("reference-async.wav")
        try writeWithSingleBuffer(samples, to: referenceURL)

        let url = directory.appendingPathComponent("async.wav")
        try await AudioProcessor().saveSamplesAsWav(samples: samples, to: url)

        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: referenceURL))
    }

    // MARK: - Decode

    func testSixteenKilohertzMonoFileDecodesToPeakNormalisedSamples() async throws {
        let pattern: [Int16] = [0, 8_192, -16_384, 4_096, -1, 1, 16_383, -8_192, 12_345, -4_321]
        let written = (0..<400).map { pattern[$0 % pattern.count] }

        let url = directory.appendingPathComponent("source.wav")
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(written.count)))
        buffer.frameLength = AVAudioFrameCount(written.count)
        let channel = try XCTUnwrap(buffer.int16ChannelData?[0])
        for (index, sample) in written.enumerated() {
            channel[index] = sample
        }
        do {
            let file = try AVAudioFile(
                forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false)
            try file.write(from: buffer)
        }

        let samples = try await AudioProcessor().processAudioToSamples(url)

        // AVAudioFile decodes 16-bit PCM as value / 32768; the importer then divides by the peak.
        let decoded = written.map { Float($0) / 32_768 }
        XCTAssertEqual(bitPatterns(samples), bitPatterns(referenceNormalization(decoded)))
        XCTAssertEqual(samples.map(abs).max(), 1)
    }
}
