import SwiftUI
import SwiftData
import AppKit

@MainActor
class MenuBarManager: ObservableObject {
    @Published var isMenuBarOnly: Bool {
        didSet {
            AppSettings.General.isMenuBarOnly = isMenuBarOnly
            updateAppActivationPolicy()
        }
    }

    private var modelContainer: ModelContainer?
    private var whisperState: WhisperState?

    init() {
        self.isMenuBarOnly = AppSettings.General.isMenuBarOnly ?? false
        updateAppActivationPolicy()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard isMenuBarOnly else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, self.isMenuBarOnly else { return }
            let hasVisibleWindows = NSApplication.shared.windows.contains {
                $0.isVisible && $0.level == .normal && !$0.styleMask.contains(.nonactivatingPanel)
            }
            if !hasVisibleWindows {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }

    func configure(modelContainer: ModelContainer, whisperState: WhisperState) {
        self.modelContainer = modelContainer
        self.whisperState = whisperState
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
            AppLogger.ui.debug("MenuBarManager was unable to locate the main window to focus")
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
        AppLogger.ui.debug("MenuBarManager navigating to \(destination, privacy: .public)")

        let aiFeaturesEnabled = AppSettings.General.enableAIEnhancementFeatures ?? false
        if !aiFeaturesEnabled && (destination == "AI Models" || destination == "Enhancement" || destination == "Text to Speech") {
            AppLogger.ui.info("MenuBarManager blocked navigation to \(destination, privacy: .public) because AI features are disabled")
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
            AppLogger.ui.error("MenuBarManager was unable to show the main window for navigation")
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
            AppLogger.ui.debug("MenuBarManager posted navigation notification for \(destination, privacy: .public)")
        }
    }

    func openHistoryWindow() {
        guard let modelContainer = modelContainer,
              let whisperState = whisperState else {
            AppLogger.ui.error("MenuBarManager dependencies were not configured before opening history window")
            return
        }
        NSApplication.shared.setActivationPolicy(.regular)
        HistoryWindowController.shared.showHistoryWindow(
            modelContainer: modelContainer,
            whisperState: whisperState
        )
    }
}
