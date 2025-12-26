import Foundation

/// Protocol for processing transcription requests
@MainActor
protocol TranscriptionProcessorProtocol {
    /// Process audio data into text
    func transcribe(audioData: Data, languageHint: String?) async throws -> TranscriptionResult

    /// Cancel current transcription
    func cancelTranscription()

    /// Get current processing state
    var isProcessing: Bool { get }
}