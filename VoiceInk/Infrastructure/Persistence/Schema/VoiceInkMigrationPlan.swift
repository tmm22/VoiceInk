import Foundation
import SwiftData

/// Migration plan for the app's SwiftData stores. With a single schema and no stages this is a
/// no-op for existing stores; it exists so that future model changes can be expressed as explicit
/// lightweight or custom stages instead of relying on inferred migration.
enum VoiceInkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [VoiceInkSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
