import Accelerate
import XCTest
@testable import VoiceInk

/// Exercises the downmix + resample + Int16 path used by CoreAudioRecorder without any audio hardware.
final class RecordingAudioFormatConverterTests: XCTestCase {
    private let inputRate = 48_000.0
    private let outputRate = 16_000.0
    private let framesPerCall: UInt32 = 512

    /// Interleaved stereo Float32 sine (identical on both channels).
    private func stereoSine(frequency: Double, frames: Int, amplitude: Float = 0.5, sampleRate: Double) -> [Float] {
        var samples = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let value = amplitude * Float(sin(2.0 * .pi * frequency * Double(frame) / sampleRate))
            samples[frame * 2] = value
            samples[frame * 2 + 1] = value
        }
        return samples
    }

    /// Runs `input` (interleaved, `channels`) through the converter in render-sized calls, then flushes.
    private func convertAll(
        _ input: [Float], channels: UInt32, inputRate: Double, outputRate: Double
    ) throws -> [Int16] {
        let converter = try XCTUnwrap(
            RecordingAudioFormatConverter(
                inputSampleRate: inputRate,
                inputChannelCount: channels,
                outputSampleRate: outputRate,
                maxInputFrames: framesPerCall
            )
        )

        var output: [Int16] = []
        let totalFrames = input.count / Int(channels)
        var offset = 0
        input.withUnsafeBufferPointer { pointer in
            while offset < totalFrames {
                let frames = min(Int(framesPerCall), totalFrames - offset)
                let chunk = converter.convert(
                    interleavedInput: pointer.baseAddress! + offset * Int(channels),
                    frameCount: UInt32(frames),
                    channelCount: channels
                )
                XCTAssertNotNil(chunk)
                if let chunk { output.append(contentsOf: chunk) }
                offset += frames
            }
        }
        let tail = try XCTUnwrap(converter.flush())
        output.append(contentsOf: tail)
        return output
    }

    private func rms(_ samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return sqrt(sum / Double(samples.count))
    }

    /// Goertzel magnitude (normalised to amplitude) of `frequency` in `samples`.
    private func goertzelAmplitude(_ samples: [Int16], frequency: Double, sampleRate: Double) -> Double {
        let n = samples.count
        let omega = 2.0 * .pi * frequency / sampleRate
        let coefficient = 2.0 * cos(omega)
        var s0 = 0.0, s1 = 0.0, s2 = 0.0
        for sample in samples {
            s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
        return 2.0 * sqrt(max(power, 0)) / Double(n)
    }

    func testDownsamplesStereo48kToMono16kWithExpectedLength() throws {
        let seconds = 1.0
        let frames = Int(inputRate * seconds)
        let input = stereoSine(frequency: 1_000, frames: frames, sampleRate: inputRate)

        let output = try convertAll(input, channels: 2, inputRate: inputRate, outputRate: outputRate)

        let expected = Double(frames) * outputRate / inputRate
        // Allow for converter priming/latency at the edges.
        XCTAssertEqual(Double(output.count), expected, accuracy: 128, "output length should be about N/3")
    }

    func testOneKilohertzToneSurvivesResampling() throws {
        let frames = Int(inputRate)  // 1 s
        let amplitude: Float = 0.5
        let input = stereoSine(frequency: 1_000, frames: frames, amplitude: amplitude, sampleRate: inputRate)

        let output = try convertAll(input, channels: 2, inputRate: inputRate, outputRate: outputRate)
        // Skip the first/last few ms to avoid filter transients.
        let steady = Array(output.dropFirst(800).dropLast(800))

        let measured = goertzelAmplitude(steady, frequency: 1_000, sampleRate: outputRate)
        let expectedAmplitude = Double(amplitude) * 32767.0
        XCTAssertEqual(measured, expectedAmplitude, accuracy: expectedAmplitude * 0.05)

        // Downmix of identical channels must not change level: RMS of a sine is A / sqrt(2).
        XCTAssertEqual(rms(steady), expectedAmplitude / sqrt(2), accuracy: expectedAmplitude * 0.05)
    }

    func testTwentyKilohertzToneIsRejectedByAntiAliasFilter() throws {
        let frames = Int(inputRate)
        let inBand = stereoSine(frequency: 1_000, frames: frames, sampleRate: inputRate)
        let outOfBand = stereoSine(frequency: 20_000, frames: frames, sampleRate: inputRate)

        let inBandOutput = try convertAll(inBand, channels: 2, inputRate: inputRate, outputRate: outputRate)
        let outOfBandOutput = try convertAll(outOfBand, channels: 2, inputRate: inputRate, outputRate: outputRate)

        let inBandRMS = rms(Array(inBandOutput.dropFirst(800).dropLast(800)))
        let aliasRMS = rms(Array(outOfBandOutput.dropFirst(800).dropLast(800)))
        XCTAssertGreaterThan(inBandRMS, 1_000)
        XCTAssertLessThan(aliasRMS, inBandRMS * 0.05, "20 kHz content must not alias into the 16 kHz output")
    }

    func testEqualRatePathDownmixesAndQuantisesLikeScalarReference() throws {
        let frames = 2_000
        var input = [Float](repeating: 0, count: frames * 2)
        var generator = SeededGenerator(seed: 5)
        for index in 0..<input.count {
            input[index] = Float.random(in: -1.2...1.2, using: &generator)  // includes clipping range
        }

        let output = try convertAll(input, channels: 2, inputRate: outputRate, outputRate: outputRate)
        XCTAssertEqual(output.count, frames)

        for frame in 0..<frames {
            let mono = (input[frame * 2] + input[frame * 2 + 1]) / 2
            let expected = Int16(max(-32768.0, min(32767.0, mono * 32767.0)))
            // vDSP accumulation order may differ by one LSB from the scalar reference.
            XCTAssertEqual(Int(output[frame]), Int(expected), accuracy: 1, "frame \(frame)")
        }
    }

    func testDownmixAveragesArbitraryChannelCounts() {
        let frames = 4
        let channels: UInt32 = 3
        let input: [Float] = [
            0.3, 0.6, 0.9,
            -0.3, -0.6, -0.9,
            1.0, 0.0, -1.0,
            0.25, 0.25, 0.25,
        ]
        var mono = [Float](repeating: 0, count: frames)
        input.withUnsafeBufferPointer { inputPointer in
            mono.withUnsafeMutableBufferPointer { monoPointer in
                RecordingAudioFormatConverter.downmix(
                    interleavedInput: inputPointer.baseAddress!,
                    frameCount: UInt32(frames),
                    channelCount: channels,
                    into: monoPointer.baseAddress!
                )
            }
        }
        XCTAssertEqual(mono[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(mono[1], -0.6, accuracy: 1e-6)
        XCTAssertEqual(mono[2], 0.0, accuracy: 1e-6)
        XCTAssertEqual(mono[3], 0.25, accuracy: 1e-6)
    }

    func testRejectsOversizedInputAndChannelMismatch() throws {
        let converter = try XCTUnwrap(
            RecordingAudioFormatConverter(
                inputSampleRate: inputRate, inputChannelCount: 2, outputSampleRate: outputRate, maxInputFrames: 64))
        let input = [Float](repeating: 0.1, count: 200 * 2)
        input.withUnsafeBufferPointer { pointer in
            XCTAssertNil(converter.convert(interleavedInput: pointer.baseAddress!, frameCount: 200, channelCount: 2))
            XCTAssertNil(converter.convert(interleavedInput: pointer.baseAddress!, frameCount: 32, channelCount: 1))
            XCTAssertNotNil(converter.convert(interleavedInput: pointer.baseAddress!, frameCount: 64, channelCount: 2))
        }
    }

    func testMeterLevelsForFullScaleSine() {
        let count = 48_000
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            samples[index] = Float(sin(2.0 * .pi * 1_000.0 * Double(index) / 48_000.0))
        }

        let levels = samples.withUnsafeBufferPointer {
            CoreAudioRecorder.meterLevels(samples: $0.baseAddress!, count: count)
        }
        XCTAssertEqual(levels.average, -3.01, accuracy: 0.05, "full-scale sine RMS is -3 dBFS")
        XCTAssertEqual(levels.peak, 0.0, accuracy: 0.01, "full-scale sine peak is 0 dBFS")
    }

    func testMeterLevelsForSilenceAreFloored() {
        let samples = [Float](repeating: 0, count: 1_024)
        let levels = samples.withUnsafeBufferPointer {
            CoreAudioRecorder.meterLevels(samples: $0.baseAddress!, count: samples.count)
        }
        XCTAssertEqual(levels.average, -120, accuracy: 0.01)
        XCTAssertEqual(levels.peak, -120, accuracy: 0.01)
    }

    func testNormalizedLevelMapsVisibleWindow() {
        XCTAssertEqual(Recorder.normalizedLevel(fromDecibels: -120), 0)
        XCTAssertEqual(Recorder.normalizedLevel(fromDecibels: -60), 0)
        XCTAssertEqual(Recorder.normalizedLevel(fromDecibels: -30), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Recorder.normalizedLevel(fromDecibels: 0), 1)
        XCTAssertEqual(Recorder.normalizedLevel(fromDecibels: 6), 1)
    }
}
