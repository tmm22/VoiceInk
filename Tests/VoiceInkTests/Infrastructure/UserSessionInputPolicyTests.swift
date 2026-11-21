import CoreGraphics
import XCTest
@testable import VoiceInk

final class UserSessionInputPolicyTests: XCTestCase {
    // MARK: - Session properties

    func testAllowsShortcutsOnlyInAnUnlockedConsoleSession() {
        XCTAssertTrue(UserSessionInputPolicy.allowsShortcutHandling(sessionProperties: Self.session()))
        XCTAssertFalse(UserSessionInputPolicy.allowsShortcutHandling(sessionProperties: Self.session(isLocked: true)))
        XCTAssertFalse(UserSessionInputPolicy.allowsShortcutHandling(sessionProperties: Self.session(isOnConsole: false)))
        XCTAssertFalse(UserSessionInputPolicy.allowsShortcutHandling(sessionProperties: Self.session(isLoginDone: false)))
        XCTAssertFalse(UserSessionInputPolicy.allowsShortcutHandling(sessionProperties: [:]))
    }

    // MARK: - Remembered answer

    func testAllowedAnswerIsRememberedUntilItsTimeToLive() {
        let session = FakeSession()
        let cache = session.makeCache()

        XCTAssertTrue(cache.allowsShortcutHandling())
        session.now += 0.1
        XCTAssertTrue(cache.allowsShortcutHandling())
        session.now += 0.39
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 1)

        session.now += 0.01
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 2)
    }

    func testUsingTheRememberedAnswerDoesNotExtendIt() {
        let session = FakeSession()
        let cache = session.makeCache()

        XCTAssertTrue(cache.allowsShortcutHandling())
        session.now += 0.49
        XCTAssertTrue(cache.allowsShortcutHandling())
        session.now += 0.02
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 2)
    }

    func testSilentSessionChangeIsSeenOnceTheAnswerExpires() {
        let session = FakeSession()
        let cache = session.makeCache()

        XCTAssertTrue(cache.allowsShortcutHandling())
        session.isAllowed = false
        session.now += 0.5

        XCTAssertFalse(cache.allowsShortcutHandling())
    }

    func testNotAllowedAnswerIsNeverRemembered() {
        let session = FakeSession()
        session.isAllowed = false
        let cache = session.makeCache()

        XCTAssertFalse(cache.allowsShortcutHandling())
        XCTAssertFalse(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 2)

        session.isAllowed = true
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 3)
    }

    func testNotAllowedAnswerDropsTheRememberedOne() {
        let session = FakeSession()
        let cache = session.makeCache(settleInterval: 0)

        XCTAssertTrue(cache.allowsShortcutHandling())
        session.now += 0.5
        session.isAllowed = false
        XCTAssertFalse(cache.allowsShortcutHandling())

        session.isAllowed = true
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 3)
    }

    func testInvalidationForcesAFreshRead() {
        let session = FakeSession()
        let cache = session.makeCache()

        XCTAssertTrue(cache.allowsShortcutHandling())
        session.isAllowed = false
        cache.invalidate()

        XCTAssertFalse(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 2)
    }

    func testAnswersStayFreshWhileASessionChangeSettles() {
        let session = FakeSession()
        let cache = session.makeCache(settleInterval: 2)

        XCTAssertTrue(cache.allowsShortcutHandling())
        cache.invalidate()

        XCTAssertTrue(cache.allowsShortcutHandling())
        session.now += 1.9
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 3)

        session.now += 0.1
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 4)
        session.now += 0.1
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 4)
    }

    func testNotAllowedAnswerAlsoStartsTheSettleInterval() {
        let session = FakeSession()
        session.isAllowed = false
        let cache = session.makeCache(settleInterval: 2)

        XCTAssertFalse(cache.allowsShortcutHandling())
        session.isAllowed = true
        XCTAssertTrue(cache.allowsShortcutHandling())
        session.now += 0.1
        XCTAssertTrue(cache.allowsShortcutHandling())

        XCTAssertEqual(session.queryCount, 3)
    }

    func testAnswerReadWhileTheSessionChangedIsNotRemembered() {
        let session = FakeSession()
        let cache = session.makeCache(settleInterval: 0)
        session.onQuery = { cache.invalidate() }

        XCTAssertTrue(cache.allowsShortcutHandling())
        session.onQuery = nil
        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 2)

        XCTAssertTrue(cache.allowsShortcutHandling())
        XCTAssertEqual(session.queryCount, 2)
    }

    func testClockMovingBackwardsIsTreatedAsExpired() {
        let session = FakeSession()
        let cache = session.makeCache()

        XCTAssertTrue(cache.allowsShortcutHandling())
        session.now -= 10
        XCTAssertTrue(cache.allowsShortcutHandling())

        XCTAssertEqual(session.queryCount, 2)
    }

    func testContinuousUptimeMovesForward() {
        let first = UserSessionInputPolicyCache.continuousUptime()
        let second = UserSessionInputPolicyCache.continuousUptime()

        XCTAssertGreaterThan(first, 0)
        XCTAssertGreaterThanOrEqual(second, first)
    }

    func testSharedRememberedAnswerAgreesWithAnAllowedSession() {
        let before = UserSessionInputPolicy.allowsShortcutHandling
        let remembered = UserSessionInputPolicy.cachedAllowsShortcutHandling
        let after = UserSessionInputPolicy.allowsShortcutHandling

        // A locked or headless session legitimately reports "not allowed".
        guard before, after else { return }
        XCTAssertTrue(remembered)
    }

    // MARK: - Per-event gate

    func testIdleEventIsAdmittedOnTheRecentAnswer() {
        let answers = FakeAnswers()
        let gate = answers.makeGate()

        XCTAssertTrue(gate.admitsEvent(requiringFreshAnswer: false))

        XCTAssertEqual(answers.recentReads, 1)
        XCTAssertEqual(answers.freshReads, 0)
    }

    func testEventDuringAHeldShortcutIsAdmittedOnAFreshAnswer() {
        let answers = FakeAnswers()
        let gate = answers.makeGate()

        XCTAssertTrue(gate.admitsEvent(requiringFreshAnswer: true))
        XCTAssertTrue(gate.confirmsShortcutPress())

        XCTAssertEqual(answers.recentReads, 0)
        XCTAssertEqual(answers.freshReads, 1)
    }

    func testEventIsRejectedWhenItsAnswerIsNotAllowed() {
        let answers = FakeAnswers()
        let gate = answers.makeGate()

        answers.recent = false
        XCTAssertFalse(gate.admitsEvent(requiringFreshAnswer: false))

        answers.recent = true
        answers.fresh = false
        XCTAssertFalse(gate.admitsEvent(requiringFreshAnswer: true))
    }

    func testPressFromAnIdleEventNeedsAFreshAnswer() {
        let answers = FakeAnswers()
        let gate = answers.makeGate()

        XCTAssertTrue(gate.admitsEvent(requiringFreshAnswer: false))
        XCTAssertTrue(gate.confirmsShortcutPress())
        XCTAssertTrue(gate.confirmsShortcutPress())

        XCTAssertEqual(answers.freshReads, 1)
    }

    func testStaleRecentAnswerCannotStartAPress() {
        let answers = FakeAnswers()
        answers.fresh = false
        let gate = answers.makeGate()

        XCTAssertTrue(gate.admitsEvent(requiringFreshAnswer: false))
        XCTAssertFalse(gate.confirmsShortcutPress())
        XCTAssertFalse(gate.confirmsShortcutPress())

        XCTAssertEqual(answers.freshReads, 2)
    }

    func testFreshAnswerDoesNotCarryOverToTheNextEvent() {
        let answers = FakeAnswers()
        let gate = answers.makeGate()

        XCTAssertTrue(gate.admitsEvent(requiringFreshAnswer: true))
        XCTAssertTrue(gate.admitsEvent(requiringFreshAnswer: false))
        answers.fresh = false

        XCTAssertFalse(gate.confirmsShortcutPress())
    }

    // MARK: - Helpers

    private static func session(
        isOnConsole: Bool = true,
        isLoginDone: Bool = true,
        isLocked: Bool = false
    ) -> [String: Any] {
        [
            kCGSessionOnConsoleKey as String: isOnConsole,
            kCGSessionLoginDoneKey as String: isLoginDone,
            "CGSSessionScreenIsLocked": isLocked,
        ]
    }
}

private final class FakeSession: @unchecked Sendable {
    var now: TimeInterval = 1_000
    var isAllowed = true
    var onQuery: (() -> Void)?
    private(set) var queryCount = 0

    func makeCache(
        timeToLive: TimeInterval = 0.5,
        settleInterval: TimeInterval = 2
    ) -> UserSessionInputPolicyCache {
        UserSessionInputPolicyCache(
            timeToLive: timeToLive,
            settleInterval: settleInterval,
            now: { self.now },
            query: {
                self.queryCount += 1
                self.onQuery?()
                return self.isAllowed
            }
        )
    }
}

private final class FakeAnswers {
    var fresh = true
    var recent = true
    private(set) var freshReads = 0
    private(set) var recentReads = 0

    func makeGate() -> ShortcutSessionGate {
        ShortcutSessionGate(
            freshAnswer: {
                self.freshReads += 1
                return self.fresh
            },
            recentAnswer: {
                self.recentReads += 1
                return self.recent
            }
        )
    }
}
