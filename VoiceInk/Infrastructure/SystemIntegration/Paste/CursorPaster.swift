import AppKit
import Carbon
import Foundation
import os

class CursorPaster {
    private static let logger = Logger(subsystem: AppLogger.subsystem, category: "CursorPaster")

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted
        /// The pasteboard changed between the transcript write and the paste; nothing was posted.
        case skippedClipboardChanged

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
        Task { @MainActor in
            notifyIfSkipped(await startPasteAtCursor(text).value)
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
    static func performPasteSession(
        _ text: String, on pasteboard: NSPasteboard = .general,
        defaults: UserDefaults = .standard,
        waitForPaste: (@MainActor () async -> Void)? = nil,
        postCommand: (@MainActor () async -> PasteResult)? = nil,
        restoreScheduler: (@MainActor (ClipboardSnapshot, String, String, Int, TimeInterval, NSPasteboard) -> Void)? = nil,
        captureSnapshot: (@MainActor (NSPasteboard) async -> (snapshot: ClipboardSnapshot, revision: Int)?)? = nil
    ) async -> PasteResult {
        let shouldRestoreClipboard = defaults.bool(forKey: "restoreClipboardAfterPaste")
        // Read the user's restore delay once, up front, so the restore path does no defaults I/O later.
        let clipboardRestoreDelay =
            shouldRestoreClipboard
            ? max(defaults.double(forKey: "clipboardRestoreDelay"), minimumClipboardRestoreDelay)
            : 0
        var savedContents: ClipboardSnapshot?
        var snapshotRevision: Int?
        if shouldRestoreClipboard {
            let captured: (snapshot: ClipboardSnapshot, revision: Int)?
            if let captureSnapshot {
                captured = await captureSnapshot(pasteboard)
            } else {
                captured = await captureStableSnapshot(of: pasteboard)
            }
            guard let captured else {
                // Cancellation is not a clipboard change; it must not show the skip warning.
                return Task.isCancelled ? .commandNotPosted : .skippedClipboardChanged
            }
            savedContents = captured.snapshot
            snapshotRevision = captured.revision
        }
        guard !Task.isCancelled else { return .commandNotPosted }
        // Revalidate immediately before overwriting: a copy made after the snapshot must neither be
        // replaced by the transcript nor later "restored" over with the older snapshot. No suspension
        // separates this check from the write below; only another process can still race it.
        if let snapshotRevision, pasteboard.changeCount != snapshotRevision {
            logger.notice("Paste skipped because the clipboard changed after its snapshot")
            return .skippedClipboardChanged
        }
        let sessionID = UUID().uuidString

        guard
            ClipboardManager.setClipboard(
                text,
                transient: shouldRestoreClipboard,
                sessionID: shouldRestoreClipboard ? sessionID : nil,
                on: pasteboard
            )
        else {
            logger.error("Failed to prepare clipboard for paste")
            return .commandNotPosted
        }
        let clipboardChangeCount = pasteboard.changeCount
        let clipboardWrittenAt = ContinuousClock.now
        defer {
            if let savedContents {
                if let restoreScheduler {
                    restoreScheduler(savedContents, text, sessionID, clipboardChangeCount, clipboardRestoreDelay, pasteboard)
                } else {
                    scheduleClipboardRestore(
                        savedContents, expectedText: text, sessionID: sessionID,
                        expectedChangeCount: clipboardChangeCount, after: clipboardRestoreDelay, on: pasteboard
                    )
                }
            }
        }

        if let waitForPaste {
            await waitForPaste()
        } else {
            await waitUntilReadyToPaste(since: clipboardWrittenAt)
        }

        guard !Task.isCancelled else {
            logger.notice("Paste cancelled before posting")
            return .commandNotPosted
        }
        // Do not paste unrelated content copied while waiting for shortcut keys to be released.
        guard
            !shouldSkipPaste(on: pasteboard, expectedChangeCount: clipboardChangeCount, expectedText: text)
        else {
            logger.notice("Paste skipped because the clipboard no longer holds the transcript")
            return .skippedClipboardChanged
        }
        if let postCommand { return await postCommand() }
        return await postPasteCommand()
    }

    /// Captures the user's clipboard for later restoration. A copy or clipboard-manager rewrite that
    /// lands during capture gets one fresh attempt; a clipboard that keeps changing is left alone and
    /// the paste is skipped rather than risk restoring stale contents over the user's newest copy.
    @MainActor
    static func captureStableSnapshot(
        of pasteboard: NSPasteboard, attempts: Int = 2,
        capture: (NSPasteboard.Name) async -> (snapshot: ClipboardSnapshot, revision: Int)? = {
            await ClipboardSnapshot.capture(name: $0)
        }
    ) async -> (snapshot: ClipboardSnapshot, revision: Int)? {
        for attempt in 1...max(1, attempts) {
            guard !Task.isCancelled else { return nil }
            if let captured = await capture(pasteboard.name),
               pasteboard.changeCount == captured.revision {
                return captured
            }
            logger.notice("Clipboard changed during snapshot capture attempt=\(attempt, privacy: .public)")
        }
        return nil
    }

    /// Permit only a stable, single plain-text rewrite. Equal text does not make RTF, HTML,
    /// attachments or additional items safe. NSPasteboard offers no atomic check-and-paste API;
    /// another process can still write after the final check and before the target reads Cmd+V.
    @MainActor
    static func shouldSkipPaste(
        on pasteboard: NSPasteboard, expectedChangeCount: Int, expectedText: String
    ) -> Bool {
        let revision = pasteboard.changeCount
        guard revision != expectedChangeCount else { return false }
        guard let items = pasteboard.pasteboardItems, items.count == 1,
              let item = items.first,
              Set(item.types).isSubset(of: ClipboardManager.plainTextPasteTypes),
              item.string(forType: .string) == expectedText else { return true }
        return pasteboard.changeCount != revision
    }

    /// Adaptive replacement for the old fixed pre-paste delay. See `PrePasteWaitPolicy`.
    @MainActor
    private static func waitUntilReadyToPaste(since clipboardWrittenAt: ContinuousClock.Instant) async {
        let outcome = await prePasteWaitPolicy.run(
            modifiersHeld: { anyModifierHeld() },
            elapsed: { secondsSince(clipboardWrittenAt) },
            sleep: { await wait($0) }
        )
        // A cancelled wait also reports the modifiers as held; nothing is posted in that case.
        if !outcome.modifiersReleased, !Task.isCancelled {
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
        expectedChangeCount: Int,
        after delay: TimeInterval,
        on pasteboard: NSPasteboard
    ) {
        Task { @MainActor in
            await wait(delay)
            savedContents.restoreIfOwned(
                to: pasteboard, expectedText: expectedText, sessionID: sessionID,
                expectedChangeCount: expectedChangeCount
            )
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
