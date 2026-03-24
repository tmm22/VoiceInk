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
            name: NSNotification.Name("HideNotchRecorder"),
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

        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        if notchPanel == nil || screenIdentifier(for: notchPanel?.screen) != screenIdentifier(for: activeScreen) {
            initializeWindow(screen: activeScreen)
        }
        self.isVisible = true
        notchPanel?.show()
    }

    func hide() {
        guard isVisible else { return }

        self.isVisible = false
        notchPanel?.orderOut(nil)
    }

    private func initializeWindow(screen: NSScreen) {
        deinitializeWindow()

        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let panel = NotchRecorderPanel(contentRect: metrics.frame)

        let notchRecorderView = NotchRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self)
            .environmentObject(whisperState.enhancementService!)

        let hostingController = NotchRecorderHostingController(rootView: notchRecorderView)
        panel.contentView = hostingController.view

        self.notchPanel = panel
        self.windowController = NSWindowController(window: panel)

        panel.orderFrontRegardless()
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
