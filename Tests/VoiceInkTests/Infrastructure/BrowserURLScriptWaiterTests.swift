import XCTest
@testable import VoiceInk

final class BrowserURLScriptWaiterTests: XCTestCase {
    func testOutcomeResolvedBeforeWaitingIsReturned() async {
        let waiter = BrowserURLScriptWaiter()
        waiter.resolve(.exited)

        let outcome = await waiter.wait()

        XCTAssertEqual(outcome, .exited)
    }

    func testFirstOutcomeWins() async {
        let waiter = BrowserURLScriptWaiter()
        waiter.resolve(.timedOut)
        waiter.resolve(.exited)
        waiter.resolve(.cancelled)

        let outcome = await waiter.wait()

        XCTAssertEqual(outcome, .timedOut)
    }

    func testWaiterResumesWhenResolvedLater() async {
        let waiter = BrowserURLScriptWaiter()
        let waiting = Task { await waiter.wait() }
        for _ in 0..<10 {
            await Task.yield()
        }

        waiter.resolve(.exited)

        let outcome = await waiting.value
        XCTAssertEqual(outcome, .exited)
    }

    func testEveryWaiterReceivesTheOutcome() async {
        let waiter = BrowserURLScriptWaiter()
        let first = Task { await waiter.wait() }
        let second = Task { await waiter.wait() }
        for _ in 0..<10 {
            await Task.yield()
        }

        waiter.resolve(.timedOut)

        let firstOutcome = await first.value
        let secondOutcome = await second.value
        let lateOutcome = await waiter.wait()
        XCTAssertEqual(firstOutcome, .timedOut)
        XCTAssertEqual(secondOutcome, .timedOut)
        XCTAssertEqual(lateOutcome, .timedOut)
    }

    func testCancellingTheWaitingTaskResolvesAsCancelled() async {
        let waiter = BrowserURLScriptWaiter()
        let waiting = Task {
            await withTaskCancellationHandler {
                await waiter.wait()
            } onCancel: {
                waiter.resolve(.cancelled)
            }
        }

        waiting.cancel()

        let outcome = await waiting.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testExitBeforeCancellationStillCountsAsExited() async {
        let waiter = BrowserURLScriptWaiter()
        waiter.resolve(.exited)
        let waiting = Task {
            await withTaskCancellationHandler {
                await waiter.wait()
            } onCancel: {
                waiter.resolve(.cancelled)
            }
        }

        waiting.cancel()

        let outcome = await waiting.value
        XCTAssertEqual(outcome, .exited)
    }
}
