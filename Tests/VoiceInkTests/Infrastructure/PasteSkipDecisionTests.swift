import AppKit
import XCTest
@testable import VoiceInk

@MainActor
final class PasteSkipDecisionTests: XCTestCase {
    func testUnchangedOwnedRevisionPastes() {
        checkRewrite(nil, shouldSkip: false)
    }

    func testRewrittenPlainTextTranscriptPastes() {
        checkRewrite("transcript", shouldSkip: false)
    }

    func testForeignContentSkips() {
        checkRewrite("user copy", shouldSkip: true)
    }

    func testEmptiedClipboardSkips() {
        checkRewrite("", shouldSkip: true)
    }

    private func checkRewrite(_ text: String?, shouldSkip: Bool) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(ClipboardManager.setClipboard("transcript", on: board))
        let revision = board.changeCount
        if let text {
            board.clearContents()
            if !text.isEmpty { board.setString(text, forType: .string) }
        }
        XCTAssertEqual(CursorPaster.shouldSkipPaste(
            on: board, expectedChangeCount: revision, expectedText: "transcript"
        ), shouldSkip)
    }
}
