import Foundation
import AppKit
class SelectedTextService {
    // Private pasteboard type to avoid clipboard history pollution
    private static let privatePasteboardType = NSPasteboard.PasteboardType("com.prakashjoshipax.VoiceInk.transient")

    static func fetchSelectedText() -> String? {

        let pasteboard = NSPasteboard.general
        let originalClipboardText = pasteboard.string(forType: .string)

        // Save original clipboard content (all UTIs with their data)
        let originalPasteboardItems = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { acc, type in
                if let data = item.data(forType: type) {
                    acc[type] = data
                }
            }
        }

        // Clear clipboard to prepare for selection detection
        pasteboard.clearContents()
        
        // Simulate Cmd+C to copy any selected text
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        cmdDown?.post(tap: .cghidEventTap)
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        // Wait for copy operation to complete
        Thread.sleep(forTimeInterval: 0.1)

        // Read the copied text
        let selectedText = pasteboard.string(forType: .string)

        // Restore original clipboard content
        pasteboard.clearContents()
        if let originalItems = originalPasteboardItems, !originalItems.isEmpty {
            let restoredItems: [NSPasteboardItem] = originalItems.compactMap { dataMap in
                guard !dataMap.isEmpty else { return nil }
                let item = NSPasteboardItem()
                for (type, data) in dataMap {
                    item.setData(data, forType: type)
                }
                return item
            }
            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            } else if let originalClipboardText {
                _ = pasteboard.setString(originalClipboardText, forType: .string)
            }
        } else if let originalClipboardText {
            _ = pasteboard.setString(originalClipboardText, forType: .string)
        }

        return selectedText
    }
}
