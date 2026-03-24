import Foundation
import AppKit
import Carbon
import os

private let logger = Logger(subsystem: "com.VoiceInk", category: "CursorPaster")

class CursorPaster {

    static func pasteAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")

        var savedContents: [(NSPasteboard.PasteboardType, Data)] = []

        if shouldRestoreClipboard {
            let currentItems = pasteboard.pasteboardItems ?? []

            for item in currentItems {
                for type in item.types {
                    if let data = item.data(forType: type) {
                        savedContents.append((type, data))
                    }
                }
            }
        }

        _ = ClipboardManager.setClipboard(text, transient: shouldRestoreClipboard)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if UserDefaults.standard.bool(forKey: "useAppleScriptPaste") || !currentInputSourceSupportsCGEventPaste() {
                pasteUsingAppleScript()
            } else {
                pasteFromClipboard()
            }
        }

        if shouldRestoreClipboard {
            let restoreDelay = UserDefaults.standard.double(forKey: "clipboardRestoreDelay")
            let delay = max(restoreDelay, 0.25)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !savedContents.isEmpty {
                    pasteboard.clearContents()
                    for (type, data) in savedContents {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
    }

    // MARK: - AppleScript paste

    // Pre-compiled AppleScript for pasting. Compiled once on first use to avoid per-paste overhead.
    private static let pasteScript: NSAppleScript? = {
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }()

    // Paste via AppleScript. Works with custom keyboard layouts (e.g. Neo2) where CGEvent-based paste fails.
    private static func pasteUsingAppleScript() {
        var error: NSDictionary?
        pasteScript?.executeAndReturnError(&error)
        if let error = error {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? -1
            logger.error("AppleScript paste failed with code \(errorNumber, privacy: .public)")
        }
    }

    // MARK: - CGEvent paste

    // Paste via CGEvent without modifying the active input source.
    private static func pasteFromClipboard() {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility not trusted — cannot paste")
            return
        }
        let source = CGEventSource(stateID: .privateState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp     = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        cmdDown?.flags = .maskCommand
        vDown?.flags   = .maskCommand
        vUp?.flags     = .maskCommand

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        logger.notice("CGEvents posted for Cmd+V")
    }

    private static func currentInputSourceSupportsCGEventPaste() -> Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let currentID = sourceID(for: currentSource) else {
            logger.error("Unable to determine current keyboard input source; falling back to AppleScript paste")
            return false
        }

        let qwertyIDs: Set<String> = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.USInternational-PC",
            "com.apple.keylayout.British",
            "com.apple.keylayout.Australian",
            "com.apple.keylayout.Canadian",
        ]
        return qwertyIDs.contains(currentID)
    }

    private static func sourceID(for source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    // MARK: - Enter key

    // Simulate pressing the Return/Enter key.
    static func pressEnter() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
