import SwiftUI
import AppKit
import os

class NotchWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
     var notchPanel: NotchRecorderPanel?
    private let whisperState: WhisperState
    private let recorder: Recorder
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "NotchWindowManager")
    
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
        
        // Get the active screen from the key window or fallback to main screen
        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        
        if initializeWindow(screen: activeScreen) {
            self.isVisible = true
            notchPanel?.show()
        }
    }
    
    func hide() {
        guard isVisible else { return }

        self.isVisible = false

        self.notchPanel?.hide { [weak self] in
            guard let self = self else { return }
            self.deinitializeWindow()
        }
    }
    
    private func initializeWindow(screen: NSScreen) -> Bool {
        deinitializeWindow()
        
        guard let enhancementService = whisperState.enhancementService else {
            logger.error("Enhancement service is missing. Cannot initialize notch recorder.")
            return false
        }
        
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
    
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
} 
