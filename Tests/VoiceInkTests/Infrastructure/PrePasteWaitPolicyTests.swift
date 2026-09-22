import XCTest
@testable import VoiceInk

/// Deterministic tests for the adaptive pre-paste wait using a simulated clock.
@available(macOS 14.0, *)
final class PrePasteWaitPolicyTests: XCTestCase {
    /// Simulated clock: `sleep` advances time instead of suspending.
    private final class FakeClock {
        var now: TimeInterval = 0
        var sleeps: [TimeInterval] = []

        func sleep(_ seconds: TimeInterval) {
            sleeps.append(seconds)
            // Quantize to whole microseconds so repeated 5 ms steps compare exactly against thresholds.
            now = ((now + seconds) * 1_000_000).rounded() / 1_000_000
        }
    }

    private let policy = PrePasteWaitPolicy(pollInterval: 0.005, maximumModifierWait: 0.150, minimumTotalDelay: 0.020)

    func testNoModifiersHeldOnlyWaitsForTheFloor() async {
        let clock = FakeClock()

        let outcome = await policy.run(
            modifiersHeld: { false },
            elapsed: { clock.now },
            sleep: { clock.sleep($0) }
        )

        XCTAssertTrue(outcome.modifiersReleased)
        XCTAssertEqual(outcome.pollCount, 0)
        XCTAssertEqual(clock.now, 0.020, accuracy: 1e-9)
        XCTAssertEqual(clock.sleeps.count, 1)
    }

    func testFloorAccountsForTimeAlreadyElapsedSinceClipboardWrite() async {
        let clock = FakeClock()
        clock.now = 0.012

        let outcome = await policy.run(
            modifiersHeld: { false },
            elapsed: { clock.now },
            sleep: { clock.sleep($0) }
        )

        XCTAssertTrue(outcome.modifiersReleased)
        XCTAssertEqual(clock.now, 0.020, accuracy: 1e-9)
        XCTAssertEqual(clock.sleeps, [0.008], "only the remainder of the floor should be slept")
    }

    func testNoSleepWhenFloorAlreadyElapsed() async {
        let clock = FakeClock()
        clock.now = 0.050

        _ = await policy.run(
            modifiersHeld: { false },
            elapsed: { clock.now },
            sleep: { clock.sleep($0) }
        )

        XCTAssertTrue(clock.sleeps.isEmpty)
        XCTAssertEqual(clock.now, 0.050, accuracy: 1e-9)
    }

    func testPollsUntilModifiersReleasedThenStops() async {
        let clock = FakeClock()
        // Held for the first 40 ms, released afterwards.
        let releaseAt: TimeInterval = 0.040

        let outcome = await policy.run(
            modifiersHeld: { clock.now < releaseAt },
            elapsed: { clock.now },
            sleep: { clock.sleep($0) }
        )

        XCTAssertTrue(outcome.modifiersReleased)
        XCTAssertEqual(outcome.pollCount, 8, "40 ms / 5 ms polls")
        // Already past the 20 ms floor, so no extra sleep after release.
        XCTAssertEqual(clock.now, 0.040, accuracy: 1e-9)
        XCTAssertLessThan(clock.now, policy.maximumModifierWait)
    }

    func testCapsWaitWhenModifierStaysHeld() async {
        let clock = FakeClock()

        let outcome = await policy.run(
            modifiersHeld: { true },
            elapsed: { clock.now },
            sleep: { clock.sleep($0) }
        )

        XCTAssertFalse(outcome.modifiersReleased)
        XCTAssertEqual(clock.now, 0.150, accuracy: 1e-9)
        XCTAssertEqual(outcome.pollCount, 30)
    }

    func testReleaseBeforeFloorStillHonoursFloor() async {
        let clock = FakeClock()
        let releaseAt: TimeInterval = 0.010

        let outcome = await policy.run(
            modifiersHeld: { clock.now < releaseAt },
            elapsed: { clock.now },
            sleep: { clock.sleep($0) }
        )

        XCTAssertTrue(outcome.modifiersReleased)
        XCTAssertEqual(outcome.pollCount, 2)
        XCTAssertEqual(clock.now, 0.020, accuracy: 1e-9)
    }

    func testModifierPressedDuringFloorIsPolledUntilRelease() async {
        let clock = FakeClock()
        let outcome = await policy.run(
            modifiersHeld: { clock.now >= 0.010 && clock.now < 0.040 },
            elapsed: { clock.now },
            sleep: { clock.sleep($0) }
        )
        XCTAssertTrue(outcome.modifiersReleased)
        XCTAssertEqual(clock.now, 0.040, accuracy: 1e-9)
        XCTAssertEqual(outcome.pollCount, 4)
    }

    func testModifierPressedDuringFloorStillHonoursCap() async {
        let clock = FakeClock()
        let outcome = await policy.run(
            modifiersHeld: { clock.now >= 0.010 },
            elapsed: { clock.now },
            sleep: { clock.sleep($0) }
        )
        XCTAssertFalse(outcome.modifiersReleased)
        XCTAssertEqual(clock.now, 0.150, accuracy: 1e-9)
    }

    func testCancellationDoesNotSpinWhenSleepReturnsImmediately() async {
        let clock = FakeClock()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await policy.run(
                modifiersHeld: { true },
                elapsed: { clock.now },
                sleep: { clock.sleep($0) }
            )
        }
        let outcome = await task.value
        XCTAssertFalse(outcome.modifiersReleased)
        XCTAssertTrue(clock.sleeps.isEmpty)
    }

    func testDefaultPolicyMatchesDocumentedTimings() {
        let defaults = PrePasteWaitPolicy.default
        XCTAssertEqual(defaults.pollInterval, 0.005, accuracy: 1e-9)
        XCTAssertEqual(defaults.maximumModifierWait, 0.150, accuracy: 1e-9)
        XCTAssertEqual(defaults.minimumTotalDelay, 0.020, accuracy: 1e-9)
    }
}
