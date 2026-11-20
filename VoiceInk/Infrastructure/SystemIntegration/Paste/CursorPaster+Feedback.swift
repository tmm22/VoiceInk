import Foundation

extension CursorPaster {
    /// Every paste entry point reports a skipped paste the same way. The transcript is already
    /// persisted before any paste starts, so History is always a valid fallback.
    @MainActor
    static func notifyIfSkipped(_ result: PasteResult, showWarning: ((String) -> Void)? = nil) {
        let title: String
        switch result {
        case .commandPosted, .commandNotPosted: return
        case .typingFailed: title = String(localized: "Typing could not start. The transcript is saved in History.")
        case .typingIncomplete: title = String(localized: "Typing stopped early. The full transcript is saved in History.")
        case .skippedClipboardChanged: title = String(localized: "Paste skipped because the clipboard changed. The transcript is saved in History.")
        }
        if let showWarning {
            showWarning(title)
            return
        }
        NotificationManager.shared.showNotification(
            title: title,
            type: .warning,
            duration: 5.0
        )
    }
}
