import Foundation
import SwiftUI

/// Protocol for managing recording sessions
@MainActor
protocol RecordingSessionProtocol {
    /// Current recording state
    var state: RecordingState { get }

    /// Start a new recording session
    func startRecording() async throws

    /// Stop the current recording session
    func stopRecording() async throws

    /// Cancel the current recording session
    func cancelRecording() async

    /// Get the recorded audio data
    func getRecordedAudio() -> Data?

    /// Clear the recorded audio
    func clearRecordedAudio()
}