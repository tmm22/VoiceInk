import Foundation
import AVFoundation
import os
import SwiftUI

/// Handles audio preprocessing tasks for transcription
@MainActor
class AudioPreprocessor {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AudioPreprocessor")

    // MARK: - Initialization
    init() {
        // Simplified initialization to avoid main actor issues
    }

    // MARK: - Audio Preprocessing

    /// Preprocess audio data for transcription
    func preprocessAudio(from url: URL) async throws -> (data: Data, duration: TimeInterval) {
        logger.info("🔄 Starting audio preprocessing for \(url.lastPathComponent)")

        // Avoid blocking the main actor for large files.
        let audioData = try await Task.detached(priority: .utility) {
            try Data(contentsOf: url, options: .mappedIfSafe)
        }.value

        // Get duration using AVFoundation
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        logger.info("✅ Audio preprocessing complete: \(durationSeconds)s, \(audioData.count) bytes")
        return (audioData, durationSeconds)
    }

    /// Validate that audio format is suitable for transcription
    private func validateAudioFormat(_ format: AVAudioFormat) throws {
        // Check sample rate (Whisper expects 16kHz)
        guard format.sampleRate >= 8000 && format.sampleRate <= 48000 else {
            throw AudioPreprocessingError.unsupportedSampleRate(format.sampleRate)
        }

        // Check channel count
        guard format.channelCount == 1 || format.channelCount == 2 else {
            throw AudioPreprocessingError.unsupportedChannelCount(Int(format.channelCount))
        }

        // Check bit depth
        guard format.isInterleaved || format.commonFormat == .pcmFormatInt16 else {
            throw AudioPreprocessingError.unsupportedBitDepth
        }

        logger.info("✅ Audio format validated: \(format.sampleRate)Hz, \(format.channelCount)ch")
    }

    /// Convert audio file to WAV format if needed
    func convertToWAVIfNeeded(inputURL: URL) async throws -> URL {
        let fileExtension = inputURL.pathExtension.lowercased()

        // If already WAV, return as-is
        if fileExtension == "wav" {
            return inputURL
        }

        // Simplified - for now just return the input URL
        // TODO: Implement proper WAV conversion
        logger.warning("⚠️ WAV conversion not implemented, returning original file")
        return inputURL
    }

    /// Clean up temporary audio files
    func cleanupTemporaryFiles(at urls: [URL]) {
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
                logger.info("🧹 Cleaned up temporary file: \(url.lastPathComponent)")
            } catch {
                logger.warning("Failed to clean up temporary file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Error Types
enum AudioPreprocessingError: LocalizedError {
    case unsupportedSampleRate(Float64)
    case unsupportedChannelCount(Int)
    case unsupportedBitDepth
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSampleRate(let rate):
            return "Unsupported sample rate: \(rate)Hz. Supported range: 8kHz-48kHz"
        case .unsupportedChannelCount(let count):
            return "Unsupported channel count: \(count). Supported: mono or stereo"
        case .unsupportedBitDepth:
            return "Unsupported audio format. 16-bit PCM required"
        case .conversionFailed(let details):
            return "Audio conversion failed: \(details)"
        }
    }
}
