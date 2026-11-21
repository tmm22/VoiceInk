import XCTest
@testable import VoiceInk

/// Feedback-sound players are built off the main actor. These tests pin the two guarantees the
/// synchronous loader gave for free: reloads take effect in request order, and a cue requested
/// after a reload started comes out of that reload's players.
final class SoundManagerLoadSequencingTests: XCTestCase {
    private typealias Completion = SoundLoadSequencer.Completion

    // MARK: - Reload ordering

    func testSingleReloadIsApplied() {
        var sequencer = SoundLoadSequencer()
        let load = sequencer.beginLoad()

        XCTAssertEqual(
            sequencer.completeLoad(load, changesPlayers: true),
            Completion(shouldApply: true, cuesToPlay: [])
        )
    }

    func testReloadsFinishingInRequestOrderAreBothApplied() {
        var sequencer = SoundLoadSequencer()
        let first = sequencer.beginLoad()
        let second = sequencer.beginLoad()

        XCTAssertTrue(sequencer.completeLoad(first, changesPlayers: true).shouldApply)
        XCTAssertTrue(sequencer.completeLoad(second, changesPlayers: true).shouldApply)
    }

    func testLaterReloadWinsOverOlderInFlightReload() {
        var sequencer = SoundLoadSequencer()
        let older = sequencer.beginLoad()
        let newer = sequencer.beginLoad()

        XCTAssertTrue(sequencer.completeLoad(newer, changesPlayers: true).shouldApply)
        XCTAssertFalse(
            sequencer.completeLoad(older, changesPlayers: true).shouldApply,
            "An older load finishing last must not replace the newer players"
        )
    }

    func testSilentPresetClearsBeforeOlderInFlightReloadLands() {
        var sequencer = SoundLoadSequencer()
        let inFlight = sequencer.beginLoad()

        // Switching to the silent preset completes synchronously.
        let silent = sequencer.beginLoad()
        XCTAssertTrue(sequencer.completeLoad(silent, changesPlayers: true).shouldApply)

        XCTAssertFalse(sequencer.completeLoad(inFlight, changesPlayers: true).shouldApply)
    }

    func testNewerReloadThatChangesNothingLeavesOlderResultInPlace() {
        var sequencer = SoundLoadSequencer()
        let older = sequencer.beginLoad()
        let newerFailed = sequencer.beginLoad()

        // A missing or unreadable file keeps the installed players, exactly as a failed
        // synchronous reload did, so the older reload still takes effect.
        XCTAssertFalse(sequencer.completeLoad(newerFailed, changesPlayers: false).shouldApply)
        XCTAssertTrue(sequencer.completeLoad(older, changesPlayers: true).shouldApply)
    }

    func testEveryCompletionOrderEndsOnTheNewestSuccessfulReload() {
        // changesPlayers per reload, in request order.
        let outcomeSets: [[Bool]] = [
            [true, true, true], [true, false, true], [true, true, false],
            [false, true, false], [true, false, false], [false, false, false],
        ]
        let completionOrders: [[Int]] = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

        for outcomes in outcomeSets {
            // The synchronous loader ended on the last reload that changed the players.
            let expectedInstalled = outcomes.lastIndex(of: true)

            for order in completionOrders {
                var sequencer = SoundLoadSequencer()
                let generations = outcomes.map { _ in sequencer.beginLoad() }
                var installed: Int?
                for index in order {
                    let completion = sequencer.completeLoad(generations[index], changesPlayers: outcomes[index])
                    if completion.shouldApply {
                        installed = index
                    }
                }

                XCTAssertEqual(installed, expectedInstalled, "outcomes=\(outcomes) completion order=\(order)")
            }
        }
    }

    // MARK: - Cues requested around a reload

    func testCueIsNotDeferredWhenNoReloadIsInFlight() {
        var sequencer = SoundLoadSequencer()

        XCTAssertFalse(sequencer.deferCueIfLoading(.start))
    }

    func testCueRequestedBeforeTheFirstReloadStartsIsNotReplayed() {
        var sequencer = SoundLoadSequencer()

        // First hotkey press: the start cue is requested before the first reload begins. It has
        // no players to use and must stay silent rather than play once they arrive.
        XCTAssertFalse(sequencer.deferCueIfLoading(.start))

        let load = sequencer.beginLoad()
        XCTAssertEqual(
            sequencer.completeLoad(load, changesPlayers: true),
            Completion(shouldApply: true, cuesToPlay: [])
        )
    }

    func testCueRequestedDuringReloadPlaysWhenItLands() {
        var sequencer = SoundLoadSequencer()
        let load = sequencer.beginLoad()

        XCTAssertTrue(sequencer.deferCueIfLoading(.cancel))
        XCTAssertEqual(
            sequencer.completeLoad(load, changesPlayers: true),
            Completion(shouldApply: true, cuesToPlay: [.cancel])
        )
        XCTAssertFalse(sequencer.deferCueIfLoading(.cancel), "Cues play immediately once the reload has landed")
    }

    func testDeferredCuesKeepRequestOrderAndAreNotRepeated() {
        var sequencer = SoundLoadSequencer()
        let load = sequencer.beginLoad()

        XCTAssertTrue(sequencer.deferCueIfLoading(.stop))
        XCTAssertTrue(sequencer.deferCueIfLoading(.start))
        XCTAssertTrue(sequencer.deferCueIfLoading(.stop))

        XCTAssertEqual(sequencer.completeLoad(load, changesPlayers: true).cuesToPlay, [.stop, .start])
    }

    func testDeferredCueIsStillDeliveredWhenReloadChangesNothing() {
        var sequencer = SoundLoadSequencer()
        let load = sequencer.beginLoad()
        XCTAssertTrue(sequencer.deferCueIfLoading(.start))

        // The reload failed, so the cue plays from whichever players are already installed.
        XCTAssertEqual(
            sequencer.completeLoad(load, changesPlayers: false),
            Completion(shouldApply: false, cuesToPlay: [.start])
        )
    }

    func testDeferredCuesWaitForTheLastInFlightReload() {
        var sequencer = SoundLoadSequencer()
        let older = sequencer.beginLoad()
        XCTAssertTrue(sequencer.deferCueIfLoading(.start))
        let newer = sequencer.beginLoad()

        XCTAssertEqual(
            sequencer.completeLoad(older, changesPlayers: true),
            Completion(shouldApply: true, cuesToPlay: [])
        )
        XCTAssertTrue(sequencer.deferCueIfLoading(.stop))
        XCTAssertEqual(
            sequencer.completeLoad(newer, changesPlayers: true),
            Completion(shouldApply: true, cuesToPlay: [.start, .stop])
        )
        XCTAssertFalse(sequencer.deferCueIfLoading(.start))
    }

    func testDeferredCuesAreDeliveredOnlyOnce() {
        var sequencer = SoundLoadSequencer()
        let first = sequencer.beginLoad()
        XCTAssertTrue(sequencer.deferCueIfLoading(.start))
        XCTAssertEqual(sequencer.completeLoad(first, changesPlayers: true).cuesToPlay, [.start])

        let second = sequencer.beginLoad()
        XCTAssertEqual(sequencer.completeLoad(second, changesPlayers: true).cuesToPlay, [])
    }
}
