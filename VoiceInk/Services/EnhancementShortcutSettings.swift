import Foundation
import SwiftUI

@MainActor
class EnhancementShortcutSettings: ObservableObject {
    static let shared = EnhancementShortcutSettings()

    @Published var isToggleEnhancementShortcutEnabled: Bool {
        didSet {
            AppSettings.Shortcuts.isToggleEnhancementShortcutEnabled = isToggleEnhancementShortcutEnabled
        }
    }
    
    private init() {
        self.isToggleEnhancementShortcutEnabled = AppSettings.Shortcuts.isToggleEnhancementShortcutEnabled
    }
}
