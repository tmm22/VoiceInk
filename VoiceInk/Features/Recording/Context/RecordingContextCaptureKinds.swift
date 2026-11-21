import Foundation

/// The context sources a recording can capture for AI enhancement.
struct RecordingContextCaptureKinds: OptionSet, Sendable {
    let rawValue: Int

    static let clipboard = RecordingContextCaptureKinds(rawValue: 1 << 0)
    static let selectedText = RecordingContextCaptureKinds(rawValue: 1 << 1)
    static let screen = RecordingContextCaptureKinds(rawValue: 1 << 2)

    static let all: RecordingContextCaptureKinds = [.clipboard, .selectedText, .screen]
}

extension RecordingContextCaptureKinds {
    /// The kinds worth capturing for a recording, given every mode configuration.
    ///
    /// `canEnhance` is false when the recording can never reach AI enhancement (there is no
    /// enhancement service, or it is an assistant follow-up). Nothing reads the snapshot then.
    ///
    /// The clipboard is always included: it is one pasteboard read, and reading it later instead
    /// could return different text. Selected text and the window screenshot are included only when
    /// an enabled mode could put them in an enhancement prompt. Every enabled mode counts, not just
    /// the current one, because trigger words, the mode popover, shortcuts and the menu bar can
    /// switch between enabled modes after the recording has started. VoiceInk Refine never receives
    /// context. A mode with no provider, or an unrecognised one, is treated as able to consume it.
    ///
    /// `pastesWithSmartPunctuation` keeps the selected-text capture regardless of modes. Smart
    /// Punctuation reads the focused field over Accessibility, on a short timeout, when the result
    /// is pasted. The selected-text capture has always sent the target application an Accessibility
    /// request first, when the recording starts, and applications such as browsers build their
    /// accessibility tree lazily on first use. Keeping the capture keeps that read as reliable as before.
    static func needed(
        for configurations: [ModeConfig],
        canEnhance: Bool,
        pastesWithSmartPunctuation: Bool
    ) -> RecordingContextCaptureKinds {
        var kinds: RecordingContextCaptureKinds = []
        if pastesWithSmartPunctuation {
            kinds.insert(.selectedText)
        }
        guard canEnhance else { return kinds }

        kinds.insert(.clipboard)
        for mode in configurations
        where mode.isEnabled
            && mode.isAIEnhancementEnabled
            && mode.selectedAIProvider != AIProvider.voiceInkRefine.rawValue
        {
            if mode.useSelectedTextContext {
                kinds.insert(.selectedText)
            }
            if mode.useScreenCapture {
                kinds.insert(.screen)
            }
        }
        return kinds
    }

    /// Of the kinds that became needed after the recording started, the ones that may still be captured.
    ///
    /// A window screenshot only reads the screen, so it is always allowed. Selected-text capture
    /// reads the frontmost application and can press its Copy menu item and briefly replace the
    /// pasteboard. It is allowed only while audio is still being recorded, so it cannot overlap
    /// pasting the result, and only while the application that was frontmost when the recording
    /// started is still frontmost, so it never reads a different application's selection.
    func capturableAfterStart(
        isRecording: Bool,
        isFrontmostApplicationUnchanged: Bool
    ) -> RecordingContextCaptureKinds {
        if isRecording && isFrontmostApplicationUnchanged {
            return self
        }
        return subtracting(.selectedText)
    }
}
