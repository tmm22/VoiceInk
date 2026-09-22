import AppKit
import XCTest
@testable import VoiceInk

@MainActor
final class ClipboardSnapshotTests: XCTestCase {
    func testChangedRevisionPreservingTextAndMarkerIsNotRestored() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        let snapshot = ClipboardSnapshot(from: pasteboard)
        let originalRevision = try writeSession(to: pasteboard)

        // A clipboard manager rewrites all representations and adds its own metadata.
        _ = try writeSession(to: pasteboard)
        let metadataType = NSPasteboard.PasteboardType("test.clipboard-manager-metadata")
        XCTAssertTrue(pasteboard.setString("new revision", forType: metadataType))
        XCTAssertNotEqual(pasteboard.changeCount, originalRevision)
        let newerRevision = pasteboard.changeCount

        XCTAssertFalse(snapshot.restoreIfOwned(
            to: pasteboard, expectedText: "transcript", sessionID: "session",
            expectedChangeCount: originalRevision
        ))
        XCTAssertEqual(pasteboard.changeCount, newerRevision)
        XCTAssertEqual(pasteboard.string(forType: .string), "transcript")
        XCTAssertEqual(pasteboard.string(forType: metadataType), "new revision")
    }

    func testUnchangedSessionRestoresAllOriginalItemsAndRepresentations() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("original", forType: .string)
        first.setData(Data([1, 2, 3]), forType: .rtf)
        let second = NSPasteboardItem()
        second.setString("second item", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([first, second]))
        let snapshot = ClipboardSnapshot(from: pasteboard)
        let revision = try writeSession(to: pasteboard)

        XCTAssertTrue(snapshot.restoreIfOwned(
            to: pasteboard, expectedText: "transcript", sessionID: "session",
            expectedChangeCount: revision
        ))
        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.string(forType: .string), "original")
        XCTAssertEqual(items.first?.data(forType: .rtf), Data([1, 2, 3]))
        XCTAssertEqual(items.last?.string(forType: .string), "second item")
        XCTAssertNil(pasteboard.string(forType: ClipboardManager.pasteSessionType))
    }

    func testNewUserCopyIsPreserved() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let snapshot = ClipboardSnapshot(from: pasteboard)
        let revision = try writeSession(to: pasteboard)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("user copy", forType: .string))
        XCTAssertFalse(snapshot.restoreIfOwned(
            to: pasteboard, expectedText: "transcript", sessionID: "session",
            expectedChangeCount: revision
        ))
        XCTAssertEqual(pasteboard.string(forType: .string), "user copy")
    }

    func testEmptyOriginalClipboardIsRestored() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let snapshot = ClipboardSnapshot(from: pasteboard)
        let revision = try writeSession(to: pasteboard)
        XCTAssertTrue(snapshot.restoreIfOwned(
            to: pasteboard, expectedText: "transcript", sessionID: "session",
            expectedChangeCount: revision
        ))
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
    }

    func testMatchingRevisionStillRequiresSessionIdentityAndText() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let snapshot = ClipboardSnapshot(from: pasteboard)
        let revision = try writeSession(to: pasteboard)
        for (text, session) in [("different text", "session"), ("transcript", "different session")] {
            XCTAssertFalse(snapshot.restoreIfOwned(
                to: pasteboard, expectedText: text, sessionID: session,
                expectedChangeCount: revision
            ))
        }
        XCTAssertEqual(pasteboard.changeCount, revision)
    }

    private func writeSession(to pasteboard: NSPasteboard) throws -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("transcript", forType: .string))
        XCTAssertTrue(item.setString("session", forType: ClipboardManager.pasteSessionType))
        XCTAssertTrue(pasteboard.writeObjects([item]))
        return pasteboard.changeCount
    }
}
