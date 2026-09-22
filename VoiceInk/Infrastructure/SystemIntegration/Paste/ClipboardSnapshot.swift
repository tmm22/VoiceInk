import AppKit
import OSLog

/// Retains all representations of the original clipboard until an owned paste can restore them.
struct ClipboardSnapshot: Sendable {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(from pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    /// Read promised/large representations away from the UI thread. Construct the pasteboard on
    /// that worker too; no AppKit object crosses the executor boundary. The caller checks revision
    /// again before writing, so a copy made during this suspension is never knowingly overwritten.
    static func capture(name: NSPasteboard.Name) async -> (snapshot: Self, revision: Int)? {
        await Task.detached(priority: .userInitiated) {
            let pasteboard = NSPasteboard(name: name)
            let revision = pasteboard.changeCount
            let snapshot = Self(from: pasteboard)
            guard pasteboard.changeCount == revision else { return nil }
            return (snapshot, revision)
        }.value
    }

    @MainActor
    @discardableResult
    func restoreIfOwned(
        to pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String,
        expectedChangeCount: Int
    ) -> Bool {
        // Clipboard managers can preserve our text and marker while rewriting other types.
        // Ownership requires the original revision as well as the session identity.
        guard pasteboard.changeCount == expectedChangeCount,
              pasteboard.string(forType: .string) == expectedText,
              pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID else {
            return false
        }
        let restoredItems = items.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }
        // Recheck after materializing the items; never intentionally replace a newer revision.
        guard pasteboard.changeCount == expectedChangeCount else { return false }
        pasteboard.clearContents()
        guard !restoredItems.isEmpty else { return true }
        let restored = pasteboard.writeObjects(restoredItems)
        if !restored {
            AppLogger.storage.warning("Failed to restore clipboard contents after paste")
        }
        return restored
    }
}
