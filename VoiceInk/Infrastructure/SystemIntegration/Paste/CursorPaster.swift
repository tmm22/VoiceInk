import AppKit
import Carbon
import Foundation
import os

class CursorPaster {
    private typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    private typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    private static let logger = Logger(subsystem: AppLogger.subsystem, category: "CursorPaster")

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }
    }

    /// Hold V for one event-loop turn; several apps drop a key whose down/up arrive back-to-back.
    private static let pasteKeyHoldDelay: TimeInterval = 0.01
    /// Never restore the clipboard before the target app has had a chance to read it.
    private static let minimumClipboardRestoreDelay: TimeInterval = 0.25
    private static let prePasteWaitPolicy = PrePasteWaitPolicy.default

    private static let watchedModifierFlags: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn, .maskHelp,
    ]

    static func pasteAtCursor(_ text: String) {
        Task {
            let pasteTask = await MainActor.run {
                startPasteAtCursor(text)
            }
            _ = await pasteTask.value
        }
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(_ text: String) -> Task<PasteResult, Never> {
        Task { @MainActor in
            await performPasteSession(text)
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    @MainActor
    private static func performPasteSession(_ text: String) async -> PasteResult {
        let pasteboard = NSPasteboard.general
        let defaults = UserDefaults.standard
        let shouldRestoreClipboard = defaults.bool(forKey: "restoreClipboardAfterPaste")
        // Read the user's restore delay once, up front, so the restore path does no defaults I/O later.
        let clipboardRestoreDelay =
            shouldRestoreClipboard
            ? max(defaults.double(forKey: "clipboardRestoreDelay"), minimumClipboardRestoreDelay)
            : 0
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []
        let sessionID = UUID().uuidString

        guard
            ClipboardManager.setClipboard(
                text,
                transient: shouldRestoreClipboard,
                sessionID: shouldRestoreClipboard ? sessionID : nil
            )
        else {
            logger.error("Failed to prepare clipboard for paste")
            return .commandNotPosted
        }
        let clipboardWrittenAt = ContinuousClock.now

        await waitUntilReadyToPaste(since: clipboardWrittenAt)

        let pasteResult = await postPasteCommand()
        if shouldRestoreClipboard {
            scheduleClipboardRestore(
                savedContents,
                expectedText: text,
                sessionID: sessionID,
                after: clipboardRestoreDelay,
                on: pasteboard
            )
        }

        return pasteResult
    }

    /// Adaptive replacement for the old fixed pre-paste delay. See `PrePasteWaitPolicy`.
    @MainActor
    private static func waitUntilReadyToPaste(since clipboardWrittenAt: ContinuousClock.Instant) async {
        let outcome = await prePasteWaitPolicy.run(
            modifiersHeld: { anyModifierHeld() },
            elapsed: { secondsSince(clipboardWrittenAt) },
            sleep: { await wait($0) }
        )
        if !outcome.modifiersReleased {
            logger.notice("Posting paste while a modifier key is still held; wait cap reached")
        }
    }

    private static func anyModifierHeld() -> Bool {
        !CGEventSource.flagsState(.combinedSessionState).intersection(watchedModifierFlags).isEmpty
    }

    private static func secondsSince(_ instant: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = ContinuousClock.now - instant
        let (seconds, attoseconds) = elapsed.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }

    private static func snapshotClipboard(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, data)
                }
                return nil
            }
        }
    }

    @MainActor
    private static func postPasteCommand() async -> PasteResult {
        if PasteMethod.current() == .appleScript {
            return pasteUsingAppleScript() ? .commandPosted : .commandNotPosted
        } else {
            return await pasteFromClipboard()
        }
    }

    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        after delay: TimeInterval,
        on pasteboard: NSPasteboard
    ) {
        Task { @MainActor in
            await wait(delay)
            guard pasteboardStillOwnedByPasteSession(pasteboard, expectedText: expectedText, sessionID: sessionID)
            else {
                return
            }
            pasteboard.clearContents()
            if !savedContents.isEmpty {
                pasteboard.writeObjects(pasteboardItems(from: savedContents))
            }
        }
    }

    private static func pasteboardStillOwnedByPasteSession(
        _ pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String
    ) -> Bool {
        pasteboard.string(forType: .string) == expectedText
            && pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
    }

    private static func pasteboardItems(from snapshot: ClipboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }

    // MARK: - AppleScript paste

    // "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
    // the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript(
        "tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode = makeScript(
        "tell application \"System Events\" to key code 9 using command down")

    // The current input source is queried lazily and cached; the cache is dropped whenever the
    // system reports an input source change so we never call TIS on every paste.
    @MainActor private static var cachedLayoutSwitchesToQWERTYOnCommand: Bool?
    @MainActor private static var inputSourceObserver: NSObjectProtocol?

    @MainActor
    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        installInputSourceObserverIfNeeded()
        if let cached = cachedLayoutSwitchesToQWERTYOnCommand {
            return cached
        }
        let value = computeLayoutSwitchesToQWERTYOnCommand()
        cachedLayoutSwitchesToQWERTYOnCommand = value
        return value
    }

    @MainActor
    private static func installInputSourceObserverIfNeeded() {
        guard inputSourceObserver == nil else { return }
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: name, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                cachedLayoutSwitchesToQWERTYOnCommand = nil
            }
        }
    }

    private static func computeLayoutSwitchesToQWERTYOnCommand() -> Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    @MainActor
    private static func pasteUsingAppleScript() -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("AppleScript paste script is unavailable")
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript paste failed: \(String(describing: error), privacy: .public)")
        }
        return error == nil
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard() async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission is required to paste with simulated key events")
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        else {
            logger.error("Failed to create Cmd+V keyboard events")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        // Events posted from one source are delivered in order, so the only gap that matters is
        // holding V for an event-loop turn between its down and up.
        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        await wait(pasteKeyHoldDelay)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)

        return .commandPosted
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Auto Send Keys

    static func performAutoSend(_ key: AutoSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
