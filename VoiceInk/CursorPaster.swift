import Foundation
import AppKit
import Carbon
import os

private let logger = Logger(subsystem: "com.VoiceInk", category: "CursorPaster")

class CursorPaster {
    private typealias ClipboardSnapshot = [(NSPasteboard.PasteboardType, Data)]

    static func pasteAtCursor(_ text: String) {
        Task { @MainActor in
            await startPasteAtCursor(text).value
        }
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(_ text: String) -> Task<Void, Never> {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = AppSettings.Clipboard.restoreClipboardAfterPaste
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []

        _ = ClipboardManager.setClipboard(text, transient: shouldRestoreClipboard)

        return Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
            postPasteCommand()

            if shouldRestoreClipboard {
                scheduleClipboardRestore(savedContents, on: pasteboard)
            }
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async {
        await startPasteAtCursor(text).value
    }

    private static func snapshotClipboard(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        var savedContents: ClipboardSnapshot = []
        let currentItems = pasteboard.pasteboardItems ?? []

        for item in currentItems {
            for type in item.types {
                if let data = item.data(forType: type) {
                    savedContents.append((type, data))
                }
            }
        }

        return savedContents
    }

    private static func postPasteCommand() {
        if AppSettings.Clipboard.useAppleScriptPaste || !currentInputSourceSupportsCGEventPaste() {
            pasteUsingAppleScript()
        } else {
            pasteFromClipboard()
        }
    }

    private static func scheduleClipboardRestore(_ savedContents: ClipboardSnapshot, on pasteboard: NSPasteboard) {
        let delay = max(AppSettings.Clipboard.clipboardRestoreDelay, 0.25)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !savedContents.isEmpty {
                pasteboard.clearContents()
                for (type, data) in savedContents {
                    pasteboard.setData(data, forType: type)
                }
            }
        }
    }

    // MARK: - AppleScript paste

    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript("tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode = makeScript("tell application \"System Events\" to key code 9 using command down")

    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return false
        }
        let name = Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String
        return name.hasSuffix("⌘")
    }

    // Paste via AppleScript. Works with custom layouts where CGEvent-based paste fails.
    private static func pasteUsingAppleScript() {
        let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
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
