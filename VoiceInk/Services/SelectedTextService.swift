import Foundation
import AppKit
import SelectedTextKit
import OSLog

class SelectedTextService {
    static func fetchSelectedText() async -> String? {
        let strategies: [TextStrategy] = [.accessibility, .menuAction]
        do {
            let selectedText = try await SelectedTextManager.shared.getSelectedText(strategies: strategies)
            return selectedText
        } catch {
            AppLogger.ui.error("Failed to get selected text: \(error)")
            return nil
        }
    }
}
