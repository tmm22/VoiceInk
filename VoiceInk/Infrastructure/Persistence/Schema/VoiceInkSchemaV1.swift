import Foundation
import SwiftData

/// Baseline versioned schema. It lists exactly the models (in the same order) that the app has
/// always passed to `Schema(...)`, so existing stores created without a `VersionedSchema` open
/// unchanged: SwiftData compares entity hashes, not the version identifier, when deciding whether
/// a store needs migration.
///
/// Future schema changes must add a `VoiceInkSchemaV2` and a stage in `VoiceInkMigrationPlan`
/// rather than editing this type.
enum VoiceInkSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    // Keep existing model order stable; append new models after synced entities.
    static var models: [any PersistentModel.Type] {
        [
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            SessionMetric.self,
        ]
    }
}
