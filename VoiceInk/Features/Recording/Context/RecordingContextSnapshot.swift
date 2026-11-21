import AppKit
import Foundation

struct RecordingContextSnapshot {
    var capturedAt = Date()
    var selectedText: String?
    var clipboardText: String?
    var screenText: String?
}

@MainActor
final class RecordingContextSnapshotStore {
    private(set) var snapshot = RecordingContextSnapshot()

    func updateSelectedText(_ text: String?) {
        snapshot.selectedText = Self.normalized(text)
    }

    func updateClipboardText(_ text: String?) {
        snapshot.clipboardText = Self.normalized(text)
    }

    func updateScreenText(_ text: String?) {
        snapshot.screenText = Self.normalized(text)
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
enum RecordingContextCaptureService {
    /// Starts one task per requested kind. The clipboard task stays first so it reads the pasteboard
    /// before the selected-text fallback can temporarily replace its contents.
    static func startCapture(
        into store: RecordingContextSnapshotStore,
        kinds: RecordingContextCaptureKinds
    ) -> [Task<Void, Never>] {
        var tasks: [Task<Void, Never>] = []

        if kinds.contains(.clipboard) {
            tasks.append(
                Task { @MainActor in
                    store.updateClipboardText(NSPasteboard.general.string(forType: .string))
                })
        }

        if kinds.contains(.selectedText) {
            tasks.append(
                Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    let selectedText = await SelectedTextService.fetchSelectedText()
                    guard !Task.isCancelled else { return }
                    store.updateSelectedText(selectedText)
                })
        }

        if kinds.contains(.screen) {
            tasks.append(
                Task { @MainActor in
                    guard CGPreflightScreenCaptureAccess(), !Task.isCancelled else { return }
                    let screenCaptureService = ScreenCaptureService()
                    let screenText = await screenCaptureService.captureAndExtractText()
                    guard !Task.isCancelled else { return }
                    store.updateScreenText(screenText)
                })
        }

        return tasks
    }
}
