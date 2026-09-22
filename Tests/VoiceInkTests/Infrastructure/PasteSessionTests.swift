import AppKit
import XCTest
@testable import VoiceInk

@MainActor
final class PasteSessionTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var defaults: UserDefaults!
    private var domain: String!

    override func setUp() async throws {
        pasteboard = .withUniqueName()
        domain = "PasteSessionTests.\(UUID())"
        defaults = UserDefaults(suiteName: domain)
        defaults.set(true, forKey: "restoreClipboardAfterPaste")
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        defaults.removePersistentDomain(forName: domain)
        pasteboard = nil
        defaults = nil
    }

    func testFeedbackOnlyReportsSkippedResultOnce() {
        var notifications: [String] = []
        for result in [CursorPaster.PasteResult.commandPosted, .commandNotPosted, .skippedClipboardChanged] {
            CursorPaster.notifyIfSkipped(result, showWarning: { notifications.append($0) })
        }
        XCTAssertEqual(notifications.count, 1)
        XCTAssertFalse(notifications[0].isEmpty)
    }

    func testRichSameTextRewriteSkipsAndPreservesNewClipboard() async {
        for type in [NSPasteboard.PasteboardType.rtf, .html, .fileURL] {
            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)
            var restored = true
            let result = await CursorPaster.performPasteSession(
                "transcript", on: pasteboard, defaults: defaults,
                waitForPaste: {
                    self.pasteboard.clearContents()
                    let item = NSPasteboardItem()
                    item.setString("transcript", forType: .string)
                    item.setString("foreign representation", forType: type)
                    XCTAssertTrue(self.pasteboard.writeObjects([item]))
                },
                postCommand: { XCTFail("Must not post foreign rich content"); return .commandPosted },
                restoreScheduler: { snapshot, text, session, revision, _, board in
                    restored = snapshot.restoreIfOwned(to: board, expectedText: text,
                        sessionID: session, expectedChangeCount: revision)
                }
            )
            XCTAssertEqual(result, .skippedClipboardChanged)
            XCTAssertFalse(restored)
            XCTAssertEqual(pasteboard.string(forType: type), "foreign representation")
        }
    }

    func testPlainTextSanitizerStillPastesWithoutRestoringOverRewrite() async {
        var posts = 0
        var restores = 0
        let result = await CursorPaster.performPasteSession(
            "transcript", on: pasteboard, defaults: defaults,
            waitForPaste: {
                self.pasteboard.clearContents()
                self.pasteboard.setString("transcript", forType: .string)
            },
            postCommand: { posts += 1; return .commandPosted },
            restoreScheduler: { snapshot, text, session, revision, _, board in
                restores += 1
                XCTAssertFalse(snapshot.restoreIfOwned(to: board, expectedText: text,
                    sessionID: session, expectedChangeCount: revision))
            }
        )
        XCTAssertEqual(result, .commandPosted)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(restores, 1)
    }

    func testUnchangedSessionRestoresRichOriginalAfterCommand() async {
        pasteboard.setString("original", forType: .string)
        pasteboard.setData(Data([1, 2, 3]), forType: .rtf)
        var posted = false
        let result = await CursorPaster.performPasteSession(
            "transcript", on: pasteboard, defaults: defaults, waitForPaste: {},
            postCommand: { posted = true; return .commandPosted },
            restoreScheduler: { snapshot, text, session, revision, delay, board in
                XCTAssertTrue(posted)
                XCTAssertGreaterThanOrEqual(delay, 0.25)
                XCTAssertTrue(snapshot.restoreIfOwned(to: board, expectedText: text,
                    sessionID: session, expectedChangeCount: revision))
            }
        )
        XCTAssertEqual(result, .commandPosted)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: .rtf), Data([1, 2, 3]))
    }

    func testCancellationAfterWriteRestoresWithoutPosting() async {
        pasteboard.setString("original", forType: .string)
        let task = Task { @MainActor in
            await CursorPaster.performPasteSession(
                "transcript", on: pasteboard, defaults: defaults,
                waitForPaste: { withUnsafeCurrentTask { $0?.cancel() } },
                postCommand: { XCTFail("Cancelled paste posted"); return .commandPosted },
                restoreScheduler: { snapshot, text, session, revision, _, board in
                    XCTAssertTrue(snapshot.restoreIfOwned(to: board, expectedText: text,
                        sessionID: session, expectedChangeCount: revision))
                }
            )
        }
        let result = await task.value
        XCTAssertEqual(result, .commandNotPosted)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testCopyAfterSnapshotIsNeitherOverwrittenNorRestoredOver() async throws {
        pasteboard.setString("original", forType: .string)
        var restoreScheduled = false
        let result = await CursorPaster.performPasteSession(
            "transcript", on: pasteboard, defaults: defaults,
            waitForPaste: { XCTFail("Must not wait after refusing to write") },
            postCommand: { XCTFail("Must not paste"); return .commandPosted },
            restoreScheduler: { _, _, _, _, _, _ in restoreScheduled = true },
            captureSnapshot: { board in
                // The snapshot is taken, then the user copies before the transcript is written.
                let captured = await CursorPaster.captureStableSnapshot(of: board)
                board.clearContents()
                board.setString("newer user copy", forType: .string)
                return captured
            }
        )
        XCTAssertEqual(result, .skippedClipboardChanged)
        XCTAssertFalse(restoreScheduled, "No restore may be scheduled over the newer copy")
        XCTAssertEqual(pasteboard.string(forType: .string), "newer user copy")
    }

    func testAdditionalPlainTextItemSkips() async {
        let result = await CursorPaster.performPasteSession(
            "transcript", on: pasteboard, defaults: defaults,
            waitForPaste: {
                self.pasteboard.clearContents()
                let items = ["transcript", "foreign"].map { text in
                    let item = NSPasteboardItem()
                    item.setString(text, forType: .string)
                    return item
                }
                self.pasteboard.writeObjects(items)
            }, postCommand: { XCTFail("Multiple items pasted"); return .commandPosted },
            restoreScheduler: { _, _, _, _, _, _ in }
        )
        XCTAssertEqual(result, .skippedClipboardChanged)
    }

    func testFailedPostStillRestoresOwnedClipboard() async {
        pasteboard.setString("original", forType: .string)
        let result = await CursorPaster.performPasteSession(
            "transcript", on: pasteboard, defaults: defaults, waitForPaste: {},
            postCommand: { .commandNotPosted },
            restoreScheduler: { snapshot, text, session, revision, _, board in
                XCTAssertTrue(snapshot.restoreIfOwned(to: board, expectedText: text,
                    sessionID: session, expectedChangeCount: revision))
            }
        )
        XCTAssertEqual(result, .commandNotPosted)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}

@MainActor
final class ClipboardSnapshotCaptureTests: XCTestCase {
    func testCopyDuringCaptureIsRetriedOnceWithFreshContents() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("before", forType: .string)
        var attempts = 0
        let snapshot = await CursorPaster.captureStableSnapshot(of: pasteboard) { name in
            attempts += 1
            let captured = await ClipboardSnapshot.capture(name: name)
            // Simulate a user copy landing while the first snapshot was being read.
            if attempts == 1 {
                pasteboard.clearContents()
                pasteboard.setString("user copy", forType: .string)
            }
            return captured
        }
        XCTAssertEqual(attempts, 2)
        let restored = NSPasteboard.withUniqueName()
        defer { restored.releaseGlobally() }
        XCTAssertTrue(ClipboardManager.setClipboard("transcript", sessionID: "session", on: restored))
        XCTAssertTrue(try XCTUnwrap(snapshot).snapshot.restoreIfOwned(
            to: restored, expectedText: "transcript", sessionID: "session",
            expectedChangeCount: restored.changeCount
        ))
        XCTAssertEqual(restored.string(forType: .string), "user copy", "The retry must hold the newest copy")
    }

    func testClipboardThatKeepsChangingIsNotCaptured() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var attempts = 0
        let snapshot = await CursorPaster.captureStableSnapshot(of: pasteboard) { name in
            attempts += 1
            let captured = await ClipboardSnapshot.capture(name: name)
            pasteboard.clearContents()
            pasteboard.setString("rewrite \(attempts)", forType: .string)
            return captured
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(snapshot)
    }
}
