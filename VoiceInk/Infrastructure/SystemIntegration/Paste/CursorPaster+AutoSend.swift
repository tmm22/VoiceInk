import Foundation

extension CursorPaster {
    /// A failed or cancelled paste must never submit whatever the target editor already contains.
    @MainActor
    static func autoSendAfterPaste(
        _ pasteTask: Task<PasteResult, Never>,
        key: AutoSendKey,
        wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(500)) },
        send: (AutoSendKey) -> Void = CursorPaster.performAutoSend
    ) async {
        guard key.isEnabled else { return }
        let result = await pasteTask.value
        guard result.didPostPasteCommand, !pasteTask.isCancelled, !Task.isCancelled else { return }
        do {
            try await wait()
        } catch {
            // Cancellation ends this delivery; never turn it into an Enter keystroke.
            return
        }
        guard !pasteTask.isCancelled, !Task.isCancelled else { return }
        send(key)
    }
}
