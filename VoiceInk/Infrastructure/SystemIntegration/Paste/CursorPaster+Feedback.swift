import Foundation

extension CursorPaster {
    /// Every paste entry point reports a skipped paste the same way. The transcript is already
    /// persisted before any paste starts, so History is always a valid fallback.
    @MainActor
    static func notifyIfSkipped(_ result: PasteResult, showWarning: ((String) -> Void)? = nil) {
        guard result == .skippedClipboardChanged else { return }
        let title = String(localized: "Paste skipped because the clipboard changed. The transcript is saved in History.")
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
