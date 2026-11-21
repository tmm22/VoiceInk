import AppKit
import CoreGraphics
import Foundation
import os

/// Defines whether the current macOS user session is safe to receive global shortcuts.
enum UserSessionInputPolicy {
    // CGSession has no public constant for this long-standing WindowServer property.
    private static let screenIsLockedKey = "CGSSessionScreenIsLocked"

    /// Reads the session from the WindowServer. This is the authoritative answer and is the
    /// one to consult whenever a shortcut is about to act.
    static var allowsShortcutHandling: Bool {
        guard let properties = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }

        return allowsShortcutHandling(sessionProperties: properties)
    }

    /// A recent "allowed" answer, for input events that cannot act on their own. It may be up
    /// to `UserSessionInputPolicyCache.defaultTimeToLive` old, so it must never be the only
    /// check in front of a shortcut press: use `allowsShortcutHandling` for that.
    static var cachedAllowsShortcutHandling: Bool {
        // The session observers are registered on the main run loop, which is also where every
        // shortcut event tap runs. Any other caller gets the authoritative answer.
        guard Thread.isMainThread else {
            return allowsShortcutHandling
        }

        return sessionObserver.cache.allowsShortcutHandling()
    }

    /// The authoritative read for an event that can act on a shortcut. A "not allowed" answer
    /// also drops the remembered one, so idle events stop being admitted on it straight away
    /// instead of when it expires.
    static var confirmedAllowsShortcutHandling: Bool {
        let isAllowed = allowsShortcutHandling
        if !isAllowed {
            sessionObserver.cache.invalidate()
        }
        return isAllowed
    }

    static func allowsShortcutHandling(sessionProperties: [String: Any]) -> Bool {
        guard booleanValue(sessionProperties[kCGSessionOnConsoleKey as String]) == true else {
            return false
        }

        guard booleanValue(sessionProperties[kCGSessionLoginDoneKey as String]) == true else {
            return false
        }

        if booleanValue(sessionProperties[screenIsLockedKey]) == true {
            return false
        }

        return true
    }

    private static let sessionObserver = UserSessionChangeObserver(
        cache: UserSessionInputPolicyCache(query: { UserSessionInputPolicy.allowsShortcutHandling })
    )

    private static func booleanValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }

        return (value as? NSNumber)?.boolValue
    }
}

/// Remembers a recent "allowed" session answer so that idle key events do not each make a
/// WindowServer round trip. "Not allowed" is never remembered, and any sign that the session
/// is changing turns remembering off until the change has settled.
final class UserSessionInputPolicyCache: Sendable {
    /// The most a remembered answer can lag the session if macOS never announces the change.
    static let defaultTimeToLive: TimeInterval = 0.5
    /// How long every answer is read fresh after a change is announced or "not allowed" is read.
    static let defaultSettleInterval: TimeInterval = 2

    private struct State {
        var allowedAt: TimeInterval?
        var cachingResumesAt: TimeInterval?
        var generation: UInt64 = 0
    }

    private let timeToLive: TimeInterval
    private let settleInterval: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let query: @Sendable () -> Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        timeToLive: TimeInterval = UserSessionInputPolicyCache.defaultTimeToLive,
        settleInterval: TimeInterval = UserSessionInputPolicyCache.defaultSettleInterval,
        now: @escaping @Sendable () -> TimeInterval = { UserSessionInputPolicyCache.continuousUptime() },
        query: @escaping @Sendable () -> Bool
    ) {
        self.timeToLive = timeToLive
        self.settleInterval = settleInterval
        self.now = now
        self.query = query
    }

    /// Seconds on a clock that keeps counting while the Mac sleeps, unlike
    /// `ProcessInfo.systemUptime`, so an answer remembered before sleep is expired on wake.
    static func continuousUptime() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    func allowsShortcutHandling() -> Bool {
        let currentTime = now()
        let timeToLive = timeToLive
        let generationToQuery: UInt64? = state.withLock { state in
            if let allowedAt = state.allowedAt {
                let age = currentTime - allowedAt
                if age >= 0, age < timeToLive {
                    return nil
                }
                state.allowedAt = nil
            }
            return state.generation
        }

        guard let generationToQuery else {
            return true
        }

        guard query() else {
            invalidate()
            return false
        }

        state.withLock { state in
            // A session change reported while the query was in flight outranks its answer.
            guard state.generation == generationToQuery else { return }

            if let cachingResumesAt = state.cachingResumesAt {
                guard currentTime >= cachingResumesAt else { return }
                state.cachingResumesAt = nil
            }

            state.allowedAt = currentTime
        }
        return true
    }

    /// Forgets the remembered answer and keeps answers fresh for the settle interval. A change
    /// notification is not ordered against the WindowServer state it announces, so an answer
    /// read right after one may still describe the session as it was before the change.
    func invalidate() {
        let cachingResumesAt = now() + settleInterval
        state.withLock { state in
            state.allowedAt = nil
            state.generation &+= 1
            state.cachingResumesAt = cachingResumesAt
        }
    }
}

/// Chooses, for each input event a shortcut monitor sees, how current the session answer has
/// to be.
///
/// Almost every event matches no shortcut and changes nothing, so it is admitted on a recent
/// answer. An event that can act is always held to a fresh WindowServer read: up front when a
/// shortcut is already held, or at the moment an idle event turns out to start a press.
///
/// A class rather than a struct so that its owner never holds exclusive access to it while a
/// session read is in progress.
final class ShortcutSessionGate {
    private let freshAnswer: () -> Bool
    private let recentAnswer: () -> Bool
    private var currentEventHasFreshAnswer = false

    init(
        freshAnswer: @escaping () -> Bool = { UserSessionInputPolicy.confirmedAllowsShortcutHandling },
        recentAnswer: @escaping () -> Bool = { UserSessionInputPolicy.cachedAllowsShortcutHandling }
    ) {
        self.freshAnswer = freshAnswer
        self.recentAnswer = recentAnswer
    }

    /// Call once at the start of every event. Pass `true` while a shortcut is held or input is
    /// being suppressed, because such an event can release, interrupt or swallow input.
    func admitsEvent(requiringFreshAnswer: Bool) -> Bool {
        currentEventHasFreshAnswer = false
        guard requiringFreshAnswer ? freshAnswer() : recentAnswer() else {
            return false
        }

        currentEventHasFreshAnswer = requiringFreshAnswer
        return true
    }

    /// Call before an admitted event starts a shortcut press, so a stale answer can never act
    /// in a locked or switched-out session. Once the event holds a fresh "allowed" answer,
    /// further presses in the same event reuse it.
    func confirmsShortcutPress() -> Bool {
        if currentEventHasFreshAnswer {
            return true
        }

        guard freshAnswer() else {
            return false
        }

        currentEventHasFreshAnswer = true
        return true
    }
}

/// Invalidates the remembered session answer whenever macOS reports that the session may be
/// about to stop accepting input.
private final class UserSessionChangeObserver: NSObject, Sendable {
    let cache: UserSessionInputPolicyCache

    private static let screenIsLockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let workspaceNotifications = [
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification,
    ]

    init(cache: UserSessionInputPolicyCache) {
        self.cache = cache
        super.init()

        // AppKit holds distributed notifications back while the app is inactive, which is the
        // normal state while the user types elsewhere, so ask for immediate delivery.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(sessionMayHaveChanged(_:)),
            name: Self.screenIsLockedNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in Self.workspaceNotifications {
            workspaceCenter.addObserver(
                self,
                selector: #selector(sessionMayHaveChanged(_:)),
                name: name,
                object: nil
            )
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func sessionMayHaveChanged(_ notification: Notification) {
        cache.invalidate()
    }
}
