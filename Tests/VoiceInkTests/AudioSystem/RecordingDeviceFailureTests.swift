import SwiftData
import XCTest
@testable import VoiceInk

@MainActor
final class RecordingDeviceFailureTests: XCTestCase {
    func testDeviceFailureCancelsStartingSession() async throws {
        try await withEngine { engine in
            engine.recordingState = .starting
            await engine.recorder.onRecordingDeviceFailure?()
            XCTAssertEqual(engine.recordingState, .idle)
            XCTAssertTrue(engine.shouldCancelRecording)
        }
    }

    func testDeviceFailureCancelsActiveCapture() async throws {
        try await withEngine { engine in
            engine.recordingState = .recording
            await engine.recorder.onRecordingDeviceFailure?()
            XCTAssertEqual(engine.recordingState, .idle)
            XCTAssertTrue(engine.shouldCancelRecording)
        }
    }

    func testLateDeviceFailureDoesNotCancelFinishedCapturePipeline() async throws {
        try await withEngine { engine in
            for state in [RecordingState.idle, .transcribing, .enhancing, .busy] {
                engine.recordingState = state
                engine.shouldCancelRecording = false
                await engine.recorder.onRecordingDeviceFailure?()
                XCTAssertEqual(engine.recordingState, state)
                XCTAssertFalse(engine.shouldCancelRecording)
            }
        }
    }

    private func withEngine(_ body: (VoiceInkEngine) async -> Void) async throws {
        let directory = FileSystemHelper.createIsolatedDirectory(prefix: "DeviceFailureModels")
        defer { FileSystemHelper.cleanupDirectory(directory) }
        let schema = Schema(versionedSchema: VoiceInkSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let whisper = WhisperModelManager(modelsDirectory: directory)
        let models = TranscriptionModelManager(
            whisperModelManager: whisper, fluidAudioModelManager: FluidAudioModelManager()
        )
        let engine = VoiceInkEngine(
            modelContext: container.mainContext, whisperModelManager: whisper,
            transcriptionModelManager: models
        )
        XCTAssertNotNil(engine.recorder.onRecordingDeviceFailure)
        await body(engine)
    }
}
