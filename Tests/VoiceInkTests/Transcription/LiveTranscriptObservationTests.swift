import Combine
import SwiftData
import XCTest
@testable import VoiceInk

/// Streaming partials must invalidate only the live-transcript leaf, not every engine observer.
@MainActor
final class LiveTranscriptObservationTests: XCTestCase {
    func testPartialsNotifyEngineObserversOnlyOnEmptinessChanges() throws {
        let directory = FileSystemHelper.createIsolatedDirectory(prefix: "LiveTranscriptModels")
        defer { FileSystemHelper.cleanupDirectory(directory) }
        let schema = Schema(versionedSchema: VoiceInkSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let whisper = WhisperModelManager(modelsDirectory: directory)
        let engine = VoiceInkEngine(
            modelContext: container.mainContext, whisperModelManager: whisper,
            transcriptionModelManager: TranscriptionModelManager(
                whisperModelManager: whisper, fluidAudioModelManager: FluidAudioModelManager())
        )

        var engineChanges = 0
        var leafChanges = 0
        var cancellables = Set<AnyCancellable>()
        engine.objectWillChange.sink { engineChanges += 1 }.store(in: &cancellables)
        engine.liveTranscript.objectWillChange.sink { leafChanges += 1 }.store(in: &cancellables)

        for partial in ["h", "he", "hel", "hel", "hello"] {
            engine.partialTranscript = partial
        }
        XCTAssertTrue(engine.hasPartialTranscript)
        XCTAssertEqual(engine.liveTranscript.text, "hello")
        XCTAssertEqual(engineChanges, 1, "Only the empty -> non-empty transition reaches engine observers")
        XCTAssertEqual(leafChanges, 4, "A repeated partial does not re-render the leaf")

        engine.partialTranscript = ""
        XCTAssertFalse(engine.hasPartialTranscript)
        XCTAssertEqual(engineChanges, 2)
        XCTAssertEqual(leafChanges, 5)
    }
}
