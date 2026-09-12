import Foundation

/// Decides how long to wait between writing the clipboard and posting Cmd+V.
///
/// Two constraints shape the wait:
/// 1. Physical modifier keys still held from the recording shortcut would be merged into the
///    synthetic Cmd+V by the window server (turning it into e.g. Cmd+Shift+V). We poll the
///    session modifier state and post as soon as everything is released, capped so a stuck
///    modifier cannot delay the paste indefinitely.
/// 2. Some apps read the pasteboard on their next run-loop turn after a change notification, so a
///    small floor is always kept between the clipboard write and the key event.
///
/// All timing inputs are injected so the policy can be exercised deterministically in tests.
struct PrePasteWaitPolicy: Sendable {
    struct Outcome: Equatable, Sendable {
        /// `true` if no modifiers were held when the wait ended, `false` if the cap was hit first.
        let modifiersReleased: Bool
        /// Number of modifier polls performed after the initial check.
        let pollCount: Int
    }

    /// Interval between modifier-state polls.
    var pollInterval: TimeInterval = 0.005
    /// Longest total time (since the clipboard write) to wait for modifiers to be released.
    var maximumModifierWait: TimeInterval = 0.150
    /// Smallest total time (since the clipboard write) before the paste command may be posted.
    var minimumTotalDelay: TimeInterval = 0.020

    static let `default` = PrePasteWaitPolicy()

    /// Runs the adaptive wait.
    ///
    /// - Parameters:
    ///   - modifiersHeld: Returns `true` while any modifier key is held.
    ///   - elapsed: Seconds elapsed since the clipboard was written.
    ///   - sleep: Suspends for the given number of seconds.
    func run(
        modifiersHeld: () -> Bool,
        elapsed: () -> TimeInterval,
        sleep: (TimeInterval) async -> Void
    ) async -> Outcome {
        var pollCount = 0
        var released = !modifiersHeld()

        while !released, elapsed() < maximumModifierWait {
            await sleep(pollInterval)
            pollCount += 1
            released = !modifiersHeld()
        }

        let remaining = minimumTotalDelay - elapsed()
        if remaining > 0 {
            await sleep(remaining)
        }

        return Outcome(modifiersReleased: released, pollCount: pollCount)
    }
}
