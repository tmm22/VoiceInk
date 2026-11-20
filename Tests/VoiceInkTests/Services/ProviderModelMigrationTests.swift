import Foundation
import XCTest
@testable import VoiceInk

final class ProviderModelMigrationTests: XCTestCase {
    func testLegacySelectionsSurviveMigrationAndUnrelatedFieldsArePreserved() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("grok-stt", forKey: "CurrentTranscriptionModel")
        let modes = [["selectedWhisperModel": "stt-rt-v5", "name": "Notes"],
                     ["selectedTranscriptionModelName": "my-local-model"]]
        defaults.set(try JSONEncoder().encode(modes), forKey: "modeConfigurationsV2")

        for _ in 0..<2 {
            StreamingKeysMigration.migrateProviderModelNames(defaults: defaults)
            XCTAssertEqual(defaults.string(forKey: "CurrentTranscriptionModel"), "grok-voice-transcribe-2.0")
            let data = try XCTUnwrap(defaults.data(forKey: "modeConfigurationsV2"))
            let result = try JSONDecoder().decode([[String: String]].self, from: data)
            XCTAssertEqual(result, [["selectedWhisperModel": "stt-async-v6", "name": "Notes"], modes[1]])
        }
    }
}
