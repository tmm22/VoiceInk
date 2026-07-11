import SwiftUI
import AppKit

@MainActor
class NotchWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
     var notchPanel: NotchRecorderPanel?
    private let whisperState: WhisperState
    private let recorder: Recorder

    init(whisperState: WhisperState, recorder: Recorder) {
        self.whisperState = whisperState
        self.recorder = recorder

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: .hideNotchRecorder,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleHideNotification() {
        hide()
    }

    func show() {
        if isVisible { return }

        guard let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            AppLogger.ui.error("Unable to show notch recorder because no display is available")
            return
        }
        if notchPanel == nil || screenIdentifier(for: notchPanel?.screen) != screenIdentifier(for: activeScreen) {
            guard initializeWindow(screen: activeScreen) else { return }
        }
        self.isVisible = true
        notchPanel?.show()
    }

    func hide() {
        guard isVisible else { return }

        self.isVisible = false
        notchPanel?.orderOut(nil)
    }

    @discardableResult
    private func initializeWindow(screen: NSScreen) -> Bool {
        guard let enhancementService = whisperState.enhancementService else {
            AppLogger.ui.error("Unable to initialize notch recorder because the enhancement service is unavailable")
            return false
        }

        deinitializeWindow()

        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let panel = NotchRecorderPanel(contentRect: metrics.frame)

        let notchRecorderView = NotchRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self)
            .environmentObject(enhancementService)

        let hostingController = NotchRecorderHostingController(rootView: notchRecorderView)
        panel.contentView = hostingController.view

        self.notchPanel = panel
        self.windowController = NSWindowController(window: panel)

        panel.orderFrontRegardless()
        return true
    }

    private func deinitializeWindow() {
        notchPanel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        notchPanel = nil
    }

    private func screenIdentifier(for screen: NSScreen?) -> NSNumber? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
}
