import Foundation
import AVFoundation
import os
import SwiftUI

/// Delegate protocol for recording session events
@MainActor
protocol RecordingSessionDelegate: AnyObject {
    func sessionDidStart()
    func sessionDidComplete(audioURL: URL)
    func sessionDidCancel()
    func sessionDidFail(error: Error)
}

/// Manages recording sessions with proper lifecycle and state management
@MainActor
class RecordingSessionManager: NSObject, ObservableObject, RecordingSessionProtocol {
    // MARK: - Published Properties
    @Published var state: RecordingState = .idle
    @Published var shouldCancel = false

    // MARK: - Private Properties
    private let recorder: Recorder
    private let recordingsDirectory: URL
    private weak var delegate: RecordingSessionDelegate?

    private var currentRecordingURL: URL?
    private var recordedAudioData: Data?

    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "RecordingSessionManager")

    // MARK: - Initialization
    init(recorder: Recorder, recordingsDirectory: URL, delegate: RecordingSessionDelegate? = nil) {
        self.recorder = recorder
        self.recordingsDirectory = recordingsDirectory
        self.delegate = delegate
        super.init()
    }

    // MARK: - RecordingSessionProtocol Implementation

    func startRecording() async throws {
        guard state == .idle else {
            throw RecordingSessionError.invalidState("Cannot start recording from state: \(state)")
        }

        shouldCancel = false
        state = .recording

        do {
            let fileName = "\(UUID().uuidString).wav"
            let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
            currentRecordingURL = permanentURL

            try await recorder.startRecording(toOutputFile: permanentURL)

            logger.info("✅ Recording session started successfully")
            await delegate?.sessionDidStart()

        } catch {
            state = .idle
            currentRecordingURL = nil
            logger.error("❌ Failed to start recording session: \(error.localizedDescription)")
            await delegate?.sessionDidFail(error: error)
            throw error
        }
    }

    func stopRecording() async throws {
        guard state == .recording else {
            throw RecordingSessionError.invalidState("Cannot stop recording from state: \(state)")
        }

        do {
            recorder.stopRecording()

            if let url = currentRecordingURL {
                // Avoid blocking the main actor for large recordings.
                recordedAudioData = try? await Task.detached(priority: .utility) {
                    try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                state = .idle
                logger.info("✅ Recording session stopped successfully")
                await delegate?.sessionDidComplete(audioURL: url)
            } else {
                state = .idle
                let error = RecordingSessionError.noRecordingURL
                logger.error("❌ No recording URL found after stopping")
                await delegate?.sessionDidFail(error: error)
                throw error
            }

        } catch {
            state = .idle
            logger.error("❌ Failed to stop recording session: \(error.localizedDescription)")
            await delegate?.sessionDidFail(error: error)
            throw error
        }
    }

    func cancelRecording() async {
        guard state == .recording else {
            logger.warning("⚠️ Cannot cancel recording from state: \(self.state)")
            return
        }

        shouldCancel = true
        recorder.stopRecording()
        state = .idle

        // Clean up the partial recording file
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        currentRecordingURL = nil
        recordedAudioData = nil

        logger.info("✅ Recording session cancelled")
        await delegate?.sessionDidCancel()
    }

    func getRecordedAudio() -> Data? {
        return recordedAudioData
    }

    func clearRecordedAudio() {
        recordedAudioData = nil
        currentRecordingURL = nil
    }

    // MARK: - Helper Methods

    /// Request microphone permission before starting recording
    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            case .denied, .restricted:
                continuation.resume(returning: false)
            @unknown default:
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - Error Types
enum RecordingSessionError: LocalizedError {
    case invalidState(String)
    case noRecordingURL
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid recording state: \(message)"
        case .noRecordingURL:
            return "No recording URL available"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}
