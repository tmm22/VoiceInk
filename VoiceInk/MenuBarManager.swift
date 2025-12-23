import SwiftUI
import AppKit

@MainActor
class MenuBarManager: ObservableObject {
    @Published var isMenuBarOnly: Bool {
        didSet {
            AppSettings.General.isMenuBarOnly = isMenuBarOnly
            updateAppActivationPolicy()
        }
    }
    
    
    init() {
        self.isMenuBarOnly = AppSettings.General.isMenuBarOnly ?? false
        updateAppActivationPolicy()
    }
    
    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }
    
    func applyActivationPolicy() {
        updateAppActivationPolicy()
    }
    
    func focusMainWindow() {
        applyActivationPolicy()
        if WindowManager.shared.showMainWindow() == nil {
            #if DEBUG
            print("MenuBarManager: Unable to locate main window to focus")
            #endif
        }
    }
    
    private func updateAppActivationPolicy() {
        let applyPolicy = { [weak self] in
            guard let self else { return }
            let application = NSApplication.shared
            if self.isMenuBarOnly {
                application.setActivationPolicy(.accessory)
                WindowManager.shared.hideMainWindow()
            } else {
                application.setActivationPolicy(.regular)
                _ = WindowManager.shared.showMainWindow()
            }
        }

        applyPolicy()
    }
    
    func openMainWindowAndNavigate(to destination: String) {
        #if DEBUG
        print("MenuBarManager: Navigating to \(destination)")
        #endif

        let aiFeaturesEnabled = AppSettings.General.enableAIEnhancementFeatures ?? false
        if !aiFeaturesEnabled && (destination == "AI Models" || destination == "Enhancement" || destination == "Text to Speech") {
            #if DEBUG
            print("MenuBarManager: AI features disabled; navigation to \(destination) blocked")
            #endif
            let alert = NSAlert()
            alert.messageText = "AI enhancements are disabled"
            alert.informativeText = "Enable AI enhancement features in Settings before accessing this workspace."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        applyActivationPolicy()
        
        guard WindowManager.shared.showMainWindow() != nil else {
            #if DEBUG
            print("MenuBarManager: Unable to show main window for navigation")
            #endif
            return
        }
        
        // Post a notification to navigate to the desired destination
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: ["destination": destination]
            )
            #if DEBUG
            print("MenuBarManager: Posted navigation notification for \(destination)")
            #endif
        }
    }
}

// Window delegate to handle window closing
class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
