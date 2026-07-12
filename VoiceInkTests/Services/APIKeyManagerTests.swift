import XCTest
@testable import VoiceInk

/// In-memory Keychain double so APIKeyManager can be tested without touching the real Keychain.
private final class MockKeychain: KeychainStoring {
    var storage: [String: String] = [:]
    /// When true, every save fails (simulates Keychain write errors).
    var failSaves = false

    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard !failSaves else { return false }
        storage[key] = value
        return true
    }

    func getString(forKey key: String) -> String? {
        storage[key]
    }

    func readString(forKey key: String) -> KeychainReadResult {
        storage[key].map(KeychainReadResult.present) ?? .absent
    }

    @discardableResult
    func delete(forKey key: String) -> Bool {
        storage.removeValue(forKey: key)
        return true
    }
}

/// Tests for APIKeyManager - Keychain-only retrieval and safe UserDefaults migration.
@available(macOS 14.0, *)
final class APIKeyManagerTests: XCTestCase {

    private let suiteName = "com.test.VoiceInk.APIKeyManagerTests"
    private let migrationCompletedKey = "APIKeyMigrationToKeychainCompleted_v3"
    private let legacyMigrationCompletedKey = "APIKeyMigrationToKeychainCompleted_v2"

    private var defaults: UserDefaults!
    private var keychain: MockKeychain!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        keychain = MockKeychain()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        keychain = nil
        super.tearDown()
    }

    // MARK: - Keychain-Only Retrieval

    func testGetAPIKeyReadsFromKeychain() {
        keychain.storage["groqAPIKey"] = "keychain-key"
        let manager = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertEqual(manager.getAPIKey(forProvider: "groq"), "keychain-key")
    }

    func testGetAPIKeyDoesNotFallBackToUserDefaults() {
        // Migration already marked complete, but a legacy key lingers in UserDefaults
        defaults.set(true, forKey: migrationCompletedKey)
        defaults.set("legacy-plaintext-key", forKey: "GROQAPIKey")

        let manager = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertNil(manager.getAPIKey(forProvider: "groq"), "Retrieval must be Keychain-only; no UserDefaults fallback")
        XCTAssertTrue(keychain.storage.isEmpty, "Read path must not write legacy keys to Keychain")
    }

    func testGetAPIKeyReturnsNilForEmptyKeychainValue() {
        keychain.storage["openAIAPIKey"] = ""
        let manager = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertNil(manager.getAPIKey(forProvider: "openai"), "Empty stored value should not count as a usable key")
    }

    // MARK: - Migration

    func testMigrationMovesLegacyKeysAndSetsCompletionFlag() {
        defaults.set("legacy-groq", forKey: "GROQAPIKey")
        defaults.set("legacy-openai", forKey: "OpenAIAPIKey")

        let manager = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertEqual(manager.getAPIKey(forProvider: "groq"), "legacy-groq")
        XCTAssertEqual(manager.getAPIKey(forProvider: "openai"), "legacy-openai")
        XCTAssertNil(defaults.string(forKey: "GROQAPIKey"), "Legacy key should be removed after successful migration")
        XCTAssertNil(defaults.string(forKey: "OpenAIAPIKey"), "Legacy key should be removed after successful migration")
        XCTAssertTrue(defaults.bool(forKey: migrationCompletedKey), "Flag should be set when all keys migrated")
    }

    func testMigrationDoesNotSetFlagWhenSaveFails() {
        defaults.set("legacy-groq", forKey: "GROQAPIKey")
        keychain.failSaves = true

        _ = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: migrationCompletedKey), "Flag must stay unset when any key fails to migrate")
        XCTAssertEqual(defaults.string(forKey: "GROQAPIKey"), "legacy-groq", "Failed key must stay in UserDefaults for retry")
    }

    func testMigrationRetriesOnNextLaunchAfterFailure() {
        defaults.set("legacy-groq", forKey: "GROQAPIKey")
        keychain.failSaves = true
        _ = APIKeyManager(keychain: keychain, userDefaults: defaults)

        // Next launch: Keychain works again
        keychain.failSaves = false
        let manager = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertEqual(manager.getAPIKey(forProvider: "groq"), "legacy-groq", "Retry should migrate the stranded key")
        XCTAssertNil(defaults.string(forKey: "GROQAPIKey"), "Legacy key should be removed once migration succeeds")
        XCTAssertTrue(defaults.bool(forKey: migrationCompletedKey), "Flag should be set once retry succeeds")
    }

    func testMigrationSkippedWhenFlagAlreadySet() {
        defaults.set(true, forKey: migrationCompletedKey)
        defaults.set("legacy-groq", forKey: "GROQAPIKey")

        _ = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertTrue(keychain.storage.isEmpty, "Migration must not run again once the flag is set")
    }

    func testV3MigrationRescuesKeysStrandedByBuggyV2Completion() {
        // Old builds set the v2 flag even when Keychain saves failed,
        // leaving plaintext keys stranded in UserDefaults.
        defaults.set(true, forKey: legacyMigrationCompletedKey)
        defaults.set("stranded-key", forKey: "GROQAPIKey")

        let manager = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertEqual(manager.getAPIKey(forProvider: "groq"), "stranded-key", "v3 migration must rescue keys stranded by the buggy v2 completion flag")
        XCTAssertNil(defaults.string(forKey: "GROQAPIKey"), "Rescued key should be removed from UserDefaults")
        XCTAssertTrue(defaults.bool(forKey: migrationCompletedKey))
    }

    func testMigrationPrefersExistingKeychainValueOverLegacyCopy() {
        keychain.storage["groqAPIKey"] = "current-keychain-key"
        defaults.set("stale-legacy-key", forKey: "GROQAPIKey")

        let manager = APIKeyManager(keychain: keychain, userDefaults: defaults)

        XCTAssertEqual(manager.getAPIKey(forProvider: "groq"), "current-keychain-key", "Existing Keychain value must never be overwritten by a legacy copy")
        XCTAssertNil(defaults.string(forKey: "GROQAPIKey"), "Stale legacy copy should still be cleaned up")
        XCTAssertTrue(defaults.bool(forKey: migrationCompletedKey))
    }
}
