import AVFoundation
import Foundation
import os

class AudioProcessor {
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "AudioProcessor")

    struct AudioFormat {
        static let targetSampleRate: Double = 16000.0
        static let targetChannels: UInt32 = 1
        static let targetBitDepth: UInt32 = 16
    }

    enum AudioProcessingError: LocalizedError {
        case invalidAudioFile
        case conversionFailed
        case exportFailed
        case unsupportedFormat
        case sampleExtractionFailed

        var errorDescription: String? {
            switch self {
            case .invalidAudioFile:
                return String(localized: "The audio file is invalid or corrupted")
            case .conversionFailed:
                return String(localized: "Failed to convert the audio format")
            case .exportFailed:
                return String(localized: "Failed to export the processed audio")
            case .unsupportedFormat:
                return String(localized: "The audio format is not supported")
            case .sampleExtractionFailed:
                return String(localized: "Failed to extract audio samples")
            }
        }
    }

    func processAudioToSamples(_ url: URL) async throws -> [Float] {
        do {
            return try readUsingAudioFile(url)
        } catch {
            // AVAudioFile can choke on some container/codec combinations that
            // the media stack can otherwise play (e.g. avfaudio error -50 on
            // certain mp4/m4a meeting recordings, issue #799). AVAssetReader
            // is a more resilient fallback for media containers and delivers
            // target LPCM directly, avoiding manual seeking and conversion.
            logger.warning(
                "AVAudioFile pipeline failed for \(url.lastPathComponent, privacy: .public): \(AppLogger.errorMetadata(error), privacy: .public). Falling back to AVAssetReader."
            )
            return try await readUsingAssetReader(url)
        }
    }

    private func readUsingAudioFile(_ url: URL) throws -> [Float] {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            throw AudioProcessingError.invalidAudioFile
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let channels = format.channelCount
        let totalFrames = audioFile.length

        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioFormat.targetSampleRate,
            channels: AudioFormat.targetChannels,
            interleaved: false
        )

        guard let outputFormat = outputFormat else {
            throw AudioProcessingError.unsupportedFormat
        }

        let chunkSize: AVAudioFrameCount = 50_000_000
        var allSamples: [Float] = []
        var currentFrame: AVAudioFramePosition = 0

        while currentFrame < totalFrames {
            let remainingFrames = totalFrames - currentFrame
            let framesToRead = min(chunkSize, AVAudioFrameCount(remainingFrames))

            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                throw AudioProcessingError.conversionFailed
            }

            audioFile.framePosition = currentFrame
            try audioFile.read(into: inputBuffer, frameCount: framesToRead)

            if sampleRate == AudioFormat.targetSampleRate && channels == AudioFormat.targetChannels {
                let chunkSamples = convertToWhisperFormat(inputBuffer)
                Self.append(chunkSamples, to: &allSamples)
            } else {
                guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
                    throw AudioProcessingError.conversionFailed
                }

                let ratio = AudioFormat.targetSampleRate / sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount)
                else {
                    throw AudioProcessingError.conversionFailed
                }

                var error: NSError?
                let status = converter.convert(
                    to: outputBuffer,
                    error: &error,
                    withInputFrom: { inNumPackets, outStatus in
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }
                )

                if error != nil {
                    throw AudioProcessingError.conversionFailed
                }

                if status == .error {
                    throw AudioProcessingError.conversionFailed
                }

                let chunkSamples = convertToWhisperFormat(outputBuffer)
                Self.append(chunkSamples, to: &allSamples)
            }

            currentFrame += AVAudioFramePosition(framesToRead)
        }

        return allSamples
    }

    private func readUsingAssetReader(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        // Match the legacy behavior of processing one stream by using the
        // primary audio track rather than attempting to mix multiple tracks.
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioProcessingError.invalidAudioFile
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioFormat.targetSampleRate,
            AVNumberOfChannelsKey: AudioFormat.targetChannels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw AudioProcessingError.conversionFailed
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? AudioProcessingError.sampleExtractionFailed
        }

        var samples: [Float] = []
        do {
            while let sampleBuffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                try validateAssetReaderOutputFormat(sampleBuffer)

                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                let byteCount = CMBlockBufferGetDataLength(blockBuffer)
                guard byteCount >= MemoryLayout<Float>.size else { continue }

                var chunk = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
                let status = chunk.withUnsafeMutableBytes { destination in
                    CMBlockBufferCopyDataBytes(
                        blockBuffer,
                        atOffset: 0,
                        dataLength: destination.count,
                        destination: destination.baseAddress!
                    )
                }
                guard status == kCMBlockBufferNoErr else {
                    throw AudioProcessingError.sampleExtractionFailed
                }
                samples.append(contentsOf: chunk)
            }
        } catch {
            reader.cancelReading()
            throw error
        }

        if reader.status == .failed {
            throw reader.error ?? AudioProcessingError.sampleExtractionFailed
        }
        if reader.status == .cancelled {
            throw CancellationError()
        }
        guard !samples.isEmpty else {
            throw AudioProcessingError.sampleExtractionFailed
        }

        // Keep the fallback output in the same normalized Float range expected
        // by the WAV export path.
        Self.normalizeToPeak(&samples)
        return samples
    }

    private func validateAssetReaderOutputFormat(_ sampleBuffer: CMSampleBuffer) throws {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw AudioProcessingError.sampleExtractionFailed
        }

        let format = streamDescription.pointee
        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isBigEndian = (format.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        let isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        guard
            format.mFormatID == kAudioFormatLinearPCM,
            abs(format.mSampleRate - AudioFormat.targetSampleRate) < 1.0,
            format.mChannelsPerFrame == AudioFormat.targetChannels,
            format.mBitsPerChannel == 32,
            isFloat,
            !isBigEndian,
            // Interleaving only changes the byte layout for multi-channel
            // audio; mono is identical either way, so don't reject it.
            format.mChannelsPerFrame == 1 || !isNonInterleaved
        else {
            throw AudioProcessingError.conversionFailed
        }
    }

    private func convertToWhisperFormat(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var samples: [Float]

        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            samples = Array(repeating: Float(0), count: frameLength)
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][frame]
                }
                samples[frame] = sum / Float(channelCount)
            }
        }

        Self.normalizeToPeak(&samples)

        return samples
    }

    /// Adopts the first chunk's storage instead of copying it; most files decode as one chunk.
    private static func append(_ chunk: [Float], to samples: inout [Float]) {
        if samples.isEmpty {
            samples = chunk
        } else {
            samples.append(contentsOf: chunk)
        }
    }

    /// Scales `samples` in place so the largest magnitude becomes 1.
    ///
    /// Yields exactly the values of the expression it replaces,
    /// `let peak = samples.map(abs).max() ?? 1; if peak > 0 { samples = samples.map { $0 / peak } }`,
    /// including its handling of NaN, without building two more full-length arrays.
    static func normalizeToPeak(_ samples: inout [Float]) {
        guard !samples.isEmpty else { return }

        samples.withUnsafeMutableBufferPointer { buffer in
            // Same scan as `Sequence.max()`: start from the first element and replace it only
            // when the next magnitude is strictly greater.
            var peak = abs(buffer[0])
            for index in 1..<buffer.count {
                let magnitude = abs(buffer[index])
                if peak < magnitude {
                    peak = magnitude
                }
            }

            guard peak > 0 else { return }
            for index in buffer.indices {
                buffer[index] = buffer[index] / peak
            }
        }
    }

    /// Frames converted and written per `AVAudioFile.write` call when exporting a WAV.
    static let wavExportBlockFrames = 1_048_576

    /// Runs off the caller's actor: a long recording takes a noticeable time to convert and write.
    func saveSamplesAsWav(samples: [Float], to url: URL) async throws {
        try Self.writeSamplesAsWav(samples: samples, to: url, framesPerBlock: Self.wavExportBlockFrames)
    }

    /// Writes `samples` as 16-bit mono PCM, converting one block at a time.
    ///
    /// Every sample goes through the same clamp, scale and truncation as before, and sequential
    /// writes append the same PCM bytes one whole-buffer write would, so the file is unchanged.
    /// Only the working memory differs: one fixed-size buffer instead of three full-length copies.
    static func writeSamplesAsWav(samples: [Float], to url: URL, framesPerBlock: Int) throws {
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: AudioFormat.targetSampleRate,
            channels: AudioFormat.targetChannels,
            interleaved: true
        )

        guard let outputFormat = outputFormat else {
            throw AudioProcessingError.unsupportedFormat
        }

        let blockFrames = min(samples.count, max(1, framesPerBlock))
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(blockFrames)),
            let channelData = buffer.int16ChannelData
        else {
            throw AudioProcessingError.conversionFailed
        }

        // Create audio file
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        try samples.withUnsafeBufferPointer { source in
            var offset = 0
            // `repeat` keeps the single zero-frame write an empty recording has always produced.
            repeat {
                let count = min(blockFrames, source.count - offset)
                if count > 0 {
                    // A zero-capacity buffer has no channel storage, so only read it when there are frames.
                    let block = channelData[0]
                    // Convert float samples to int16
                    for index in 0..<count {
                        block[index] = Int16(max(-1.0, min(1.0, source[offset + index])) * Float(Int16.max))
                    }
                }
                buffer.frameLength = AVAudioFrameCount(count)
                try audioFile.write(from: buffer)
                offset += count
            } while offset < source.count
        }
    }
}
