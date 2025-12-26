import Foundation
import AVFoundation
import os

/// Manages audio buffer operations and memory management
@MainActor
class AudioBufferManager: ObservableObject {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AudioBufferManager")

    private var audioBuffers: [URL: AVAudioPCMBuffer] = [:]
    private var bufferPool = Set<AVAudioPCMBuffer>()

    // MARK: - Buffer Management

    /// Load audio data from URL into a buffer
    func loadBuffer(from url: URL) async throws -> AVAudioPCMBuffer {
        // Check if buffer is already cached
        if let cachedBuffer = audioBuffers[url] {
            return cachedBuffer
        }

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioBufferError.bufferCreationFailed
        }

        try audioFile.read(into: buffer)

        // Cache the buffer
        audioBuffers[url] = buffer

        logger.info("✅ Loaded audio buffer from \(url.lastPathComponent), frames: \(frameCount)")
        return buffer
    }

    /// Convert audio buffer to Data for processing
    func bufferToData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let format = buffer.format

        guard format.isInterleaved else {
            throw AudioBufferError.unsupportedFormat("Non-interleaved formats not supported")
        }

        let channelCount = Int(format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let bytesPerFrame = format.isInterleaved ? Int(format.streamDescription.pointee.mBytesPerFrame) : 0

        guard let data = buffer.int16ChannelData else {
            throw AudioBufferError.noChannelData
        }

        // Convert to WAV data
        let dataSize = frameLength * bytesPerFrame
        let wavData = Data(bytes: data[0], count: dataSize)

        return wavData
    }

    /// Convert audio file to WAV format if needed
    func convertToWAV(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)

        guard let exportSession = exportSession else {
            throw AudioBufferError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .wav

        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        logger.info("✅ Converted audio to WAV: \(outputURL.lastPathComponent)")
    }

    /// Clear cached buffers for a specific URL
    func clearBuffer(for url: URL) {
        audioBuffers.removeValue(forKey: url)
        logger.info("🧹 Cleared buffer cache for \(url.lastPathComponent)")
    }

    /// Clear all cached buffers
    func clearAllBuffers() {
        audioBuffers.removeAll()
        bufferPool.removeAll()
        logger.info("🧹 Cleared all buffer caches")
    }

    /// Get buffer information for debugging
    func getBufferInfo(for url: URL) -> (frameCount: UInt32, format: String)? {
        guard let buffer = audioBuffers[url] else { return nil }

        let format = buffer.format
        return (buffer.frameLength, "\(format.sampleRate)Hz, \(format.channelCount)ch")
    }

    // MARK: - Memory Management

    deinit {
        // Direct cleanup without calling main actor methods
        audioBuffers.removeAll()
        bufferPool.removeAll()
    }
}

// MARK: - Error Types
enum AudioBufferError: LocalizedError {
    case bufferCreationFailed
    case unsupportedFormat(String)
    case noChannelData
    case exportSessionCreationFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .unsupportedFormat(let details):
            return "Unsupported audio format: \(details)"
        case .noChannelData:
            return "No channel data available in buffer"
        case .exportSessionCreationFailed:
            return "Failed to create audio export session"
        }
    }
}