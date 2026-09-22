import AVFoundation
import Accelerate
import Foundation
import os

/// Converts interleaved Float32 capture audio into Int16 mono at the transcription sample rate.
///
/// Downmix uses vDSP; sample-rate conversion uses `AVAudioConverter` (band-limited, so 48 kHz -> 16 kHz
/// no longer aliases); quantisation to Int16 uses vDSP with the same scale/clip semantics on both the
/// equal-rate and resampling paths. All buffers are allocated once in `init` and reused per call, so
/// `convert` and `flush` do not allocate. Not thread-safe: callers serialise on one processing queue.
final class RecordingAudioFormatConverter {
    let inputSampleRate: Double
    let inputChannelCount: UInt32
    let outputSampleRate: Double
    let maxInputFrames: UInt32
    /// Maximum number of Int16 frames a single `convert` or `flush` call can produce.
    let outputCapacity: UInt32

    var isResampling: Bool { converter != nil }

    private let logger = Logger(subsystem: AppLogger.subsystem, category: "RecordingAudioFormatConverter")

    private let converter: AVAudioConverter?
    /// Float32 mono at the input rate. Doubles as the downmix target on both paths.
    private let monoInputBuffer: AVAudioPCMBuffer
    /// Float32 mono at the output rate (only used when resampling).
    private let resampledBuffer: AVAudioPCMBuffer?
    /// Float32 scratch for the Int16 quantisation step.
    private let quantiseScratch: UnsafeMutablePointer<Float32>
    private let int16Output: UnsafeMutablePointer<Int16>

    private var pendingInput: AVAudioPCMBuffer?
    private var isFlushing = false
    private var inputBlock: AVAudioConverterInputBlock!

    /// Extra output frames beyond `ceil(maxInputFrames * ratio)` so the converter can release latency.
    private static let outputMargin: UInt32 = 1024

    init?(
        inputSampleRate: Double,
        inputChannelCount: UInt32,
        outputSampleRate: Double,
        maxInputFrames: UInt32
    ) {
        guard inputSampleRate > 0, outputSampleRate > 0, inputChannelCount > 0, maxInputFrames > 0,
            let monoInputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: inputSampleRate, channels: 1, interleaved: false),
            let monoInputBuffer = AVAudioPCMBuffer(pcmFormat: monoInputFormat, frameCapacity: maxInputFrames)
        else {
            return nil
        }

        self.inputSampleRate = inputSampleRate
        self.inputChannelCount = inputChannelCount
        self.outputSampleRate = outputSampleRate
        self.maxInputFrames = maxInputFrames
        self.monoInputBuffer = monoInputBuffer

        let ratio = outputSampleRate / inputSampleRate
        let capacity = UInt32(ceil(Double(maxInputFrames) * ratio)) + Self.outputMargin

        if inputSampleRate == outputSampleRate {
            converter = nil
            resampledBuffer = nil
            outputCapacity = max(maxInputFrames, capacity)
        } else {
            guard let monoOutputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: outputSampleRate, channels: 1, interleaved: false),
                let converter = AVAudioConverter(from: monoInputFormat, to: monoOutputFormat),
                let resampledBuffer = AVAudioPCMBuffer(pcmFormat: monoOutputFormat, frameCapacity: capacity)
            else {
                return nil
            }
            converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            self.converter = converter
            self.resampledBuffer = resampledBuffer
            outputCapacity = capacity
        }

        quantiseScratch = UnsafeMutablePointer<Float32>.allocate(capacity: Int(outputCapacity))
        int16Output = UnsafeMutablePointer<Int16>.allocate(capacity: Int(outputCapacity))

        // Stored once so per-call conversions do not allocate a closure context. The converter keeps
        // asking for input until its output buffer is full or we report `.noDataNow`/`.endOfStream`.
        inputBlock = { [unowned self] _, outStatus in
            if let buffer = self.pendingInput {
                self.pendingInput = nil
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = self.isFlushing ? .endOfStream : .noDataNow
            return nil
        }
    }

    deinit {
        quantiseScratch.deallocate()
        int16Output.deallocate()
    }

    /// Converts `frameCount` interleaved frames. Returns a view of the Int16 mono output valid until the
    /// next call, or `nil` when the input does not fit or conversion failed.
    func convert(
        interleavedInput: UnsafePointer<Float32>,
        frameCount: UInt32,
        channelCount: UInt32
    ) -> UnsafeBufferPointer<Int16>? {
        guard frameCount > 0, frameCount <= maxInputFrames, channelCount == inputChannelCount,
            let mono = monoInputBuffer.floatChannelData?[0]
        else {
            return nil
        }

        Self.downmix(
            interleavedInput: interleavedInput,
            frameCount: frameCount,
            channelCount: channelCount,
            into: mono
        )
        monoInputBuffer.frameLength = frameCount

        guard let converter, let resampledBuffer else {
            return quantise(from: mono, frameCount: frameCount)
        }

        pendingInput = monoInputBuffer
        let succeeded = runConverter(converter, into: resampledBuffer)
        pendingInput = nil
        guard succeeded, let resampled = resampledBuffer.floatChannelData?[0] else {
            return nil
        }
        return quantise(from: resampled, frameCount: resampledBuffer.frameLength)
    }

    /// Emits any frames still held inside the sample-rate converter and resets it for further use.
    /// Returns an empty view (not `nil`) when there is nothing to flush.
    func flush() -> UnsafeBufferPointer<Int16>? {
        guard let converter, let resampledBuffer else {
            return UnsafeBufferPointer(start: int16Output, count: 0)
        }

        pendingInput = nil
        isFlushing = true
        let succeeded = runConverter(converter, into: resampledBuffer)
        isFlushing = false
        converter.reset()

        guard succeeded, let resampled = resampledBuffer.floatChannelData?[0] else { return nil }
        return quantise(from: resampled, frameCount: resampledBuffer.frameLength)
    }

    /// Drops any internal converter state (for example when a recording starts).
    func reset() {
        pendingInput = nil
        isFlushing = false
        converter?.reset()
    }

    // MARK: - Steps

    /// Averages `channelCount` interleaved channels into `mono` using one vDSP pass per channel.
    static func downmix(
        interleavedInput: UnsafePointer<Float32>,
        frameCount: UInt32,
        channelCount: UInt32,
        into mono: UnsafeMutablePointer<Float32>
    ) {
        let length = vDSP_Length(frameCount)
        let stride = vDSP_Stride(channelCount)

        guard channelCount > 1 else {
            mono.update(from: interleavedInput, count: Int(frameCount))
            return
        }

        var scale = 1.0 / Float32(channelCount)
        vDSP_vsmul(interleavedInput, stride, &scale, mono, 1, length)
        for channel in 1..<Int(channelCount) {
            vDSP_vsma(interleavedInput + channel, stride, &scale, mono, 1, mono, 1, length)
        }
    }

    private func runConverter(_ converter: AVAudioConverter, into output: AVAudioPCMBuffer) -> Bool {
        output.frameLength = 0
        var error: NSError?
        let status = converter.convert(to: output, error: &error, withInputFrom: inputBlock)
        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return true
        case .error:
            logger.error(
                "AVAudioConverter failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return false
        @unknown default:
            return false
        }
    }

    private func quantise(from source: UnsafePointer<Float32>, frameCount: UInt32) -> UnsafeBufferPointer<Int16> {
        let count = Int(min(frameCount, outputCapacity))
        PCMSampleConversion.convert(float: source, count: count, into: int16Output, scratch: quantiseScratch)
        return UnsafeBufferPointer(start: int16Output, count: count)
    }
}
