import Foundation
import AVFoundation
import os

/// Handles post-transcription processing of results
class TranscriptionResultProcessor {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "TranscriptionResultProcessor")

    // MARK: - Result Processing

    /// Process raw transcription text into final result
    func processResult(
        rawText: String,
        audioURL: URL,
        modelName: String,
        transcriptionDuration: TimeInterval
    ) async throws -> (text: String, duration: TimeInterval) {
        logger.info("🔄 Processing transcription result")

        // Apply text filtering
        var processedText = TranscriptionOutputFilter.filter(rawText)
        logger.info("📝 Applied output filter")

        // Apply text formatting if enabled
        if AppSettings.TranscriptionSettings.isTextFormattingEnabled {
            processedText = WhisperTextFormatter.format(processedText)
            logger.info("📝 Applied text formatting")
        }

        // Apply word replacements
        processedText = WordReplacementService.shared.applyReplacements(to: processedText)
        logger.info("📝 Applied word replacements")

        // Trim whitespace
        processedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get audio duration
        let duration = try await getAudioDuration(from: audioURL)

        logger.info("✅ Result processing complete: \(processedText.count) characters, \(duration)s")
        return (processedText, duration)
    }

    /// Get audio duration from file
    private func getAudioDuration(from url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    /// Create final TranscriptionResult with all metadata
    func createTranscriptionResult(
        text: String,
        enhancedText: String? = nil,
        duration: TimeInterval,
        transcriptionDuration: TimeInterval,
        enhancementDuration: TimeInterval? = nil,
        modelName: String,
        promptName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        aiRequestSystemMessage: String? = nil,
        aiRequestUserMessage: String? = nil,
        aiContextJSON: String? = nil,
        aiEnhancementModelName: String? = nil
    ) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            enhancedText: enhancedText,
            duration: duration,
            transcriptionDuration: transcriptionDuration,
            enhancementDuration: enhancementDuration,
            modelName: modelName,
            promptName: promptName,
            powerModeName: powerModeName,
            powerModeEmoji: powerModeEmoji,
            aiRequestSystemMessage: aiRequestSystemMessage,
            aiRequestUserMessage: aiRequestUserMessage,
            aiContextJSON: aiContextJSON,
            aiEnhancementModelName: aiEnhancementModelName
        )
    }
}