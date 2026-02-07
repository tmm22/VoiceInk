import Foundation
import AppKit
#if canImport(SelectedTextKit)
import SelectedTextKit
#endif
import OSLog

class SelectedTextService {
    static func fetchSelectedText() async -> String? {
        #if canImport(SelectedTextKit)
        let strategies: [TextStrategy] = [.accessibility, .menuAction]
        do {
            let selectedText = try await SelectedTextManager.shared.getSelectedText(strategies: strategies)
            return selectedText
        } catch {
            AppLogger.ui.error("Failed to get selected text: \(error)")
            return nil
        }
        #else
        AppLogger.ui.warning("SelectedTextKit module unavailable; skipping selected text capture")
        return nil
        #endif
    }
}
