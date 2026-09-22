import SwiftData
import XCTest
@testable import VoiceInk

/// Verifies that introducing `VoiceInkSchemaV1` + `VoiceInkMigrationPlan` is a no-op for stores
/// that were created by earlier builds with a plain, unversioned `Schema([...])`.
@available(macOS 14.0, *)
final class VoiceInkSchemaMigrationTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileSystemHelper.createIsolatedDirectory(prefix: "VoiceInkSchemaMigration")
    }

    override func tearDown() async throws {
        FileSystemHelper.cleanupDirectory(directory)
        directory = nil
        try await super.tearDown()
    }

    func testVersionedSchemaListsTheSameModelsInTheSameOrder() {
        let names = VoiceInkSchemaV1.models.map { String(describing: $0) }
        XCTAssertEqual(names, ["Transcription", "VocabularyWord", "WordReplacement", "SessionMetric"])
        XCTAssertEqual(VoiceInkSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(VoiceInkMigrationPlan.schemas.map { $0.versionIdentifier }, [Schema.Version(1, 0, 0)])
        XCTAssertTrue(VoiceInkMigrationPlan.stages.isEmpty)
    }

    func testVersionedSchemaHasIdenticalEntitiesToLegacySchema() {
        let legacy = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let versioned = Schema(versionedSchema: VoiceInkSchemaV1.self)

        XCTAssertEqual(
            Set(legacy.entities.map(\.name)),
            Set(versioned.entities.map(\.name))
        )
        for entity in legacy.entities {
            let counterpart = versioned.entities.first { $0.name == entity.name }
            XCTAssertNotNil(counterpart, "missing entity \(entity.name)")
            XCTAssertEqual(
                Set(entity.properties.map(\.name)),
                Set(counterpart?.properties.map(\.name) ?? []),
                "property set differs for \(entity.name)"
            )
        }
    }

    @MainActor
    func testOpeningLegacyMultiStoreContainerWithMigrationPlanKeepsData() throws {
        // 1. Create the stores the way the app did before versioned schemas existed.
        let legacySchema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let transcriptionID: UUID
        do {
            let container = try ModelContainer(for: legacySchema, configurations: configurations(schema: legacySchema))
            let context = container.mainContext
            let transcription = Transcription(text: "legacy transcript", duration: 1.5)
            transcriptionID = transcription.id
            context.insert(transcription)
            context.insert(VocabularyWord(word: "VoiceInk"))
            context.insert(WordReplacement(originalText: "teh", replacementText: "the"))
            context.insert(
                SessionMetric(
                    transcriptionId: transcriptionID,
                    wordCount: 2,
                    audioDuration: 1.5,
                    transcriptionModelName: "test",
                    transcriptionDuration: 0.4,
                    speedFactor: nil,
                    modeName: nil,
                    aiEnhancementModelName: nil,
                    enhancementDuration: nil
                )
            )
            try context.save()
        }

        // 2. Reopen with the versioned schema and migration plan exactly as the app does now.
        let versionedSchema = Schema(versionedSchema: VoiceInkSchemaV1.self)
        let reopened = try ModelContainer(
            for: versionedSchema,
            migrationPlan: VoiceInkMigrationPlan.self,
            configurations: configurations(schema: versionedSchema)
        )
        let context = reopened.mainContext

        let transcriptions = try context.fetch(FetchDescriptor<Transcription>())
        XCTAssertEqual(transcriptions.map(\.text), ["legacy transcript"])
        XCTAssertEqual(transcriptions.first?.id, transcriptionID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyWord>()).map(\.word), ["VoiceInk"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<WordReplacement>()).map(\.replacementText), ["the"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionMetric>()).map(\.transcriptionId), [transcriptionID])

        // 3. Writes through the reopened container still work.
        context.insert(VocabularyWord(word: "Whisper"))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VocabularyWord>()), 2)
    }

    /// Mirrors `VoiceInkApp.createPersistentContainer`: three on-disk stores, one per model group.
    private func configurations(schema: Schema) -> [ModelConfiguration] {
        [
            ModelConfiguration(
                "default",
                schema: Schema([Transcription.self]),
                url: directory.appendingPathComponent("default.store"),
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                "dictionary",
                schema: Schema([VocabularyWord.self, WordReplacement.self]),
                url: directory.appendingPathComponent("dictionary.store"),
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                "stats",
                schema: Schema([SessionMetric.self]),
                url: directory.appendingPathComponent("stats.store"),
                cloudKitDatabase: .none
            ),
        ]
    }
}
