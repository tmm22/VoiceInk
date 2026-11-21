import Foundation
import XCTest
@testable import VoiceInk

/// Key-presence decisions behind "is this provider connected?": the two-probe Keychain existence
/// check and the short positive-only memo used for custom AI provider keys. Pure logic, no Keychain.
final class ProviderConnectionKeyPresenceTests: XCTestCase {
    private let probeResults: [Bool?] = [true, false, nil]

    /// The existence check as it was written before the second probe became conditional.
    private func originalPresence(local: Bool?, synced: Bool?) -> Bool? {
        if local == true { return true }
        if synced == true { return true }
        return local == false && synced == false ? false : nil
    }

    // MARK: - Two-probe existence check

    func testDataProtectionNamespaceKeepsBothProbesAndTheOriginalAnswer() {
        for local in probeResults {
            for synced in probeResults {
                var syncedProbes = 0
                let result = APIKeyManager.combinedPresence(local: local, namespaceHonorsSyncable: true) {
                    syncedProbes += 1
                    return synced
                }

                XCTAssertEqual(result, originalPresence(local: local, synced: synced))
                XCTAssertEqual(syncedProbes, local == true ? 0 : 1, "local=\(String(describing: local))")
            }
        }
    }

    func testLoginKeychainNamespaceSkipsOnlyTheRepeatOfASuccessfulNotFound() {
        var syncedProbes = 0
        let absent = APIKeyManager.combinedPresence(local: false, namespaceHonorsSyncable: false) {
            syncedProbes += 1
            return false
        }

        XCTAssertEqual(absent, false)
        XCTAssertEqual(syncedProbes, 0, "The second probe would repeat the query that just answered")
        // Repeating an identical query returns the same "not found", so the answer is unchanged.
        XCTAssertEqual(absent, originalPresence(local: false, synced: false))
    }

    func testLoginKeychainNamespaceStillRetriesAFailedProbe() {
        for synced in probeResults {
            var syncedProbes = 0
            let result = APIKeyManager.combinedPresence(local: nil, namespaceHonorsSyncable: false) {
                syncedProbes += 1
                return synced
            }

            XCTAssertEqual(syncedProbes, 1)
            XCTAssertEqual(result, originalPresence(local: nil, synced: synced))
        }

        // A failed read is never reported as "absent", even when the retry says "not found".
        XCTAssertNil(APIKeyManager.combinedPresence(local: nil, namespaceHonorsSyncable: false) { false })
        XCTAssertNil(APIKeyManager.combinedPresence(local: nil, namespaceHonorsSyncable: false) { nil })
        XCTAssertEqual(APIKeyManager.combinedPresence(local: nil, namespaceHonorsSyncable: false) { true }, true)
    }

    func testPresentKeyNeverNeedsTheSecondProbe() {
        for honorsSyncable in [true, false] {
            var syncedProbes = 0
            let result = APIKeyManager.combinedPresence(local: true, namespaceHonorsSyncable: honorsSyncable) {
                syncedProbes += 1
                return false
            }

            XCTAssertEqual(result, true)
            XCTAssertEqual(syncedProbes, 0)
        }
    }

    // MARK: - Positive-only presence memo

    func testMemoRemembersAPositiveAnswerUntilItsLifetimeEnds() {
        var memo = PositivePresenceMemo<String>(lifetime: .seconds(5))
        let start = ContinuousClock.now

        XCTAssertFalse(memo.isFresh("key", now: start))

        memo.record(true, for: "key", now: start)
        XCTAssertTrue(memo.isFresh("key", now: start))
        XCTAssertTrue(memo.isFresh("key", now: start.advanced(by: .milliseconds(4_999))))
        XCTAssertFalse(memo.isFresh("key", now: start.advanced(by: .seconds(5))))
        XCTAssertFalse(memo.isFresh("key", now: start.advanced(by: .seconds(60))))
    }

    func testMemoNeverRemembersAnAbsentAnswer() {
        var memo = PositivePresenceMemo<String>(lifetime: .seconds(5))
        let start = ContinuousClock.now

        memo.record(false, for: "key", now: start)
        XCTAssertFalse(memo.isFresh("key", now: start))

        // A later absent or unreadable answer also drops an earlier positive one.
        memo.record(true, for: "key", now: start)
        memo.record(false, for: "key", now: start.advanced(by: .seconds(1)))
        XCTAssertFalse(memo.isFresh("key", now: start.advanced(by: .seconds(1))))
    }

    func testInvalidationDropsOnlyThatKey() {
        var memo = PositivePresenceMemo<String>(lifetime: .seconds(5))
        let start = ContinuousClock.now
        memo.record(true, for: "saved-or-deleted", now: start)
        memo.record(true, for: "untouched", now: start)

        memo.invalidate("saved-or-deleted")
        memo.invalidate("never-recorded")

        XCTAssertFalse(memo.isFresh("saved-or-deleted", now: start))
        XCTAssertTrue(memo.isFresh("untouched", now: start))
    }

    func testRecordingAgainRestartsTheLifetime() {
        var memo = PositivePresenceMemo<String>(lifetime: .seconds(5))
        let start = ContinuousClock.now

        memo.record(true, for: "key", now: start)
        memo.record(true, for: "key", now: start.advanced(by: .seconds(4)))

        XCTAssertTrue(memo.isFresh("key", now: start.advanced(by: .seconds(8))))
        XCTAssertFalse(memo.isFresh("key", now: start.advanced(by: .seconds(9))))
    }
}
