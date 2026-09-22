import XCTest
@testable import VoiceInk

@MainActor
final class PasteAutoSendTests: XCTestCase {
    func testFailedPasteDoesNotWaitOrSubmitExistingText() async {
        var waited = false
        var sent = false
        await CursorPaster.autoSendAfterPaste(
            Task { .commandNotPosted }, key: .enter,
            wait: { waited = true }, send: { _ in sent = true }
        )
        XCTAssertFalse(waited)
        XCTAssertFalse(sent)
    }

    func testSkippedPasteAfterClipboardChangeDoesNotSubmitExistingText() async {
        XCTAssertFalse(CursorPaster.PasteResult.skippedClipboardChanged.didPostPasteCommand)
        await CursorPaster.autoSendAfterPaste(
            Task { .skippedClipboardChanged }, key: .enter,
            wait: { XCTFail("Skipped paste should not schedule auto-send") },
            send: { _ in XCTFail("Skipped paste must not submit text") }
        )
    }

    func testSuccessfulPasteWaitsBeforeSendingConfiguredKey() async {
        var events: [String] = []
        var sentKey: AutoSendKey?
        await CursorPaster.autoSendAfterPaste(
            Task { .commandPosted }, key: .commandEnter,
            wait: { events.append("wait") },
            send: { sentKey = $0; events.append("send") }
        )
        XCTAssertEqual(events, ["wait", "send"])
        XCTAssertEqual(sentKey, .commandEnter)
    }

    func testCancelledPasteThatPostedKeyDownDoesNotAutoSend() async {
        let pasteTask = Task<CursorPaster.PasteResult, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            // Key-up still has to be posted even if cancellation arrives after key-down.
            return .commandPosted
        }
        await CursorPaster.autoSendAfterPaste(
            pasteTask, key: .enter,
            wait: { XCTFail("Cancelled paste should not schedule auto-send") },
            send: { _ in XCTFail("Cancelled paste must not submit text") }
        )
    }

    func testDisabledAutoSendDoesNotPostAKey() async {
        await CursorPaster.autoSendAfterPaste(
            Task { .commandPosted }, key: .none,
            wait: { XCTFail("Disabled auto-send should not wait") },
            send: { _ in XCTFail("Disabled auto-send should not post a key") }
        )
    }

    func testCancelledDelayDoesNotPostAKey() async {
        await CursorPaster.autoSendAfterPaste(
            Task { .commandPosted }, key: .enter,
            wait: { throw CancellationError() },
            send: { _ in XCTFail("Cancellation must not submit existing text") }
        )
    }

    func testCancellationEvenWithNonthrowingWaitDoesNotPostAKey() async {
        let task = Task {
            await CursorPaster.autoSendAfterPaste(
                Task { .commandPosted }, key: .enter,
                wait: { withUnsafeCurrentTask { $0?.cancel() } },
                send: { _ in XCTFail("Cancelled delivery must not post a key") }
            )
        }
        await task.value
    }
}
