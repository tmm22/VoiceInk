import Foundation

/// A short-lived memo of "this key is present" answers.
///
/// Only positive answers are remembered. An absent or unreadable key is asked for again on the next
/// call, so a key that has just been added is never hidden by the memo and a failed Keychain read is
/// never remembered as "absent". Owners invalidate an entry whenever they write or delete its key.
struct PositivePresenceMemo<Key: Hashable> {
    let lifetime: Duration
    private var expirations: [Key: ContinuousClock.Instant] = [:]

    init(lifetime: Duration) {
        self.lifetime = lifetime
    }

    /// True while a positive answer recorded for `key` has not expired.
    func isFresh(_ key: Key, now: ContinuousClock.Instant = .now) -> Bool {
        guard let expires = expirations[key] else { return false }
        return expires > now
    }

    /// Remembers a positive answer for `lifetime`; any other answer clears the entry.
    mutating func record(_ isPresent: Bool, for key: Key, now: ContinuousClock.Instant = .now) {
        expirations[key] = isPresent ? now.advanced(by: lifetime) : nil
    }

    mutating func invalidate(_ key: Key) {
        expirations[key] = nil
    }
}
