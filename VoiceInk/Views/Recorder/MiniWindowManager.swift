import SwiftUI
import AppKit

@MainActor
class MiniWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
    private var miniPanel: MiniRecorderPanel?
    private let whisperState: WhisperState
    private let recorder: Recorder

    init(whisperState: WhisperState, recorder: Recorder) {
        self.whisperState = whisperState
        self.recorder = recorder
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: NSNotification.Name("HideMiniRecorder"),
            object: nil
        )
    }

    @objc private func handleHideNotification() {
        hide()
    }

    func show() {
        if isVisible { return }

        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        if miniPanel == nil || screenIdentifier(for: miniPanel?.screen) != screenIdentifier(for: activeScreen) {
            initializeWindow(screen: activeScreen)
        }
        self.isVisible = true
        miniPanel?.show()
    }

    func hide() {
        guard isVisible else { return }

        self.isVisible = false
        miniPanel?.orderOut(nil)
    }

    private func initializeWindow(screen: NSScreen) {
        deinitializeWindow()

        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        let panel = MiniRecorderPanel(contentRect: metrics)

        let miniRecorderView = MiniRecorderView(whisperState: whisperState, recorder: recorder)
            .environmentObject(self)
            .environmentObject(whisperState.enhancementService!)

        let hostingController = NSHostingController(rootView: miniRecorderView)
        panel.contentView = hostingController.view

        self.miniPanel = panel
        self.windowController = NSWindowController(window: panel)

        panel.orderFrontRegardless()
    }

    private func deinitializeWindow() {
        miniPanel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        miniPanel = nil
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
