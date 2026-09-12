import AVFoundation
import XCTest
@testable import VoiceInk

/// Parity tests for the vectorised PCM conversions against the scalar reference they replaced.
final class PCMSampleConversionTests: XCTestCase {
    private let tolerance: Float = 1e-6

    private func scalarReference(_ samples: [Int16]) -> [Float] {
        samples.map { max(-1.0, min(Float(Int16(littleEndian: $0)) / 32767.0, 1.0)) }
    }

    private func randomSamples(count: Int, seed: UInt64) -> [Int16] {
        var generator = SeededGenerator(seed: seed)
        var samples = (0..<count).map { _ in Int16.random(in: Int16.min...Int16.max, using: &generator) }
        // Force the extremes and zero into the set regardless of the draw.
        samples[0] = Int16.min
        samples[1] = Int16.max
        samples[2] = 0
        samples[3] = -1
        samples[4] = 1
        return samples
    }

    private func littleEndianData(_ samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    func testFloatSamplesMatchScalarReferenceIncludingExtremes() {
        let samples = randomSamples(count: 10_007, seed: 42)
        let expected = scalarReference(samples)
        let data = littleEndianData(samples)

        let actual = data.withUnsafeBytes { PCMSampleConversion.floatSamples(fromPCM16LittleEndian: $0) }

        XCTAssertEqual(actual.count, expected.count)
        for index in 0..<expected.count {
            XCTAssertEqual(actual[index], expected[index], accuracy: tolerance, "sample \(index)")
        }
        // Int16.min must clip to exactly -1 and Int16.max map to exactly +1.
        XCTAssertEqual(actual[0], -1.0)
        XCTAssertEqual(actual[1], 1.0)
        XCTAssertEqual(actual[2], 0.0)
    }

    func testTrailingOddByteIsIgnored() {
        let samples = randomSamples(count: 33, seed: 7)
        var data = littleEndianData(samples)
        data.append(0x7F)

        let actual = data.withUnsafeBytes { PCMSampleConversion.floatSamples(fromPCM16LittleEndian: $0) }
        XCTAssertEqual(actual.count, samples.count)
    }

    func testUnalignedInputMatchesAlignedInput() {
        let samples = randomSamples(count: 1_001, seed: 99)
        let expected = scalarReference(samples)
        // Prefix one byte so the sample bytes start at an odd address.
        var data = Data([0xAA])
        data.append(littleEndianData(samples))

        let actual = data.withUnsafeBytes { raw in
            PCMSampleConversion.floatSamples(fromPCM16LittleEndian: UnsafeRawBufferPointer(rebasing: raw[1...]))
        }

        XCTAssertEqual(actual.count, expected.count)
        for index in 0..<expected.count {
            XCTAssertEqual(actual[index], expected[index], accuracy: tolerance)
        }
    }

    func testPCMAudioConverterEntryPointsMatchReference() {
        let samples = randomSamples(count: 4_096, seed: 3)
        let expected = scalarReference(samples)
        let data = littleEndianData(samples)

        let floats = PCMAudioConverter.float32Samples(fromPCM16Data: data)
        XCTAssertEqual(floats.count, expected.count)
        for index in 0..<expected.count {
            XCTAssertEqual(floats[index], expected[index], accuracy: tolerance)
        }

        guard let buffer = PCMAudioConverter.pcmBuffer(fromPCM16Data: data),
            let channel = buffer.floatChannelData?[0]
        else {
            return XCTFail("pcmBuffer returned nil")
        }
        XCTAssertEqual(Int(buffer.frameLength), expected.count)
        XCTAssertEqual(buffer.format.sampleRate, 16000)
        XCTAssertEqual(buffer.format.channelCount, 1)
        for index in 0..<expected.count {
            XCTAssertEqual(channel[index], expected[index], accuracy: tolerance)
        }

        XCTAssertNil(PCMAudioConverter.pcmBuffer(fromPCM16Data: Data()))
        XCTAssertNil(PCMAudioConverter.pcmBuffer(fromPCM16Data: Data([0x01])))
    }

    func testAudioSampleReaderMatchesReferenceAcrossChunkBoundaries() throws {
        let samples = randomSamples(count: 20_001, seed: 11)
        let expected = scalarReference(samples)

        var file = Data(repeating: 0x52, count: 44)  // header is skipped, contents irrelevant
        file.append(littleEndianData(samples))
        file.append(0x01)  // dangling odd byte at end of file must be ignored

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pcm-reader-\(UUID().uuidString).wav")
        try file.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Odd chunk size forces the carry-byte path on every chunk.
        let actual = try AudioSampleReader.readPCM16LE(from: url, chunkSize: 1_001)
        XCTAssertEqual(actual.count, expected.count)
        for index in 0..<expected.count {
            XCTAssertEqual(actual[index], expected[index], accuracy: tolerance, "sample \(index)")
        }

        let defaultChunked = try AudioSampleReader.readPCM16LE(from: url)
        XCTAssertEqual(defaultChunked, actual)
    }

    func testAudioSampleReaderRejectsShortHeader() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pcm-reader-short-\(UUID().uuidString).wav")
        try Data(repeating: 0, count: 10).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try AudioSampleReader.readPCM16LE(from: url))
    }

    func testFloatToInt16MatchesScalarClipAndTruncate() {
        let input: [Float] = [0, 1, -1, 1.5, -1.5, 0.5, -0.5, 0.00001, -0.00001, 0.99999, 1.0 / 32767.0]
        let expected: [Int16] = input.map { sample in
            let scaled = sample * 32767.0
            return Int16(max(-32768.0, min(32767.0, scaled)))
        }

        var output = [Int16](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { inputPointer in
            output.withUnsafeMutableBufferPointer { outputPointer in
                PCMSampleConversion.convert(
                    float: inputPointer.baseAddress!, count: input.count, into: outputPointer.baseAddress!)
            }
        }
        XCTAssertEqual(output, expected)
    }
}

/// Deterministic generator so failures are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
