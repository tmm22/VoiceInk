import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @State private var isHovering = false
    @State private var activePopover: ActivePopoverState = .none
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage("enableAIEnhancementFeatures") private var enableAIEnhancementFeatures = false
    
    private var menuBarHeight: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.top > 0 {
                return screen.safeAreaInsets.top
            }
            return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
        }
        return NSStatusBar.system.thickness
    }
    
    private var exactNotchWidth: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.left > 0 {
                return screen.safeAreaInsets.left * 2
            }
            return 200
        }
        return 200
    }
    
    private var leftSection: some View {
        HStack(spacing: 12) {
            if enableAIEnhancementFeatures {
                RecorderPromptButton(
                    activePopover: $activePopover,
                    buttonSize: 22,
                    padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                )
            }

            RecorderPowerModeButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )

            Spacer()
        }
        .frame(width: 64)
        .padding(.leading, 16)
    }
    
    private var centerSection: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: exactNotchWidth)
            .contentShape(Rectangle())
    }
    
    private var rightSection: some View {
        HStack(spacing: 8) {
            Spacer()
            statusDisplay
        }
        .frame(width: 64)
        .padding(.trailing, 16)
    }
    
    private var statusDisplay: some View {
        HStack(spacing: 8) {
            RecorderStatusDisplay(
                currentState: whisperState.recordingState,
                audioMeter: recorder.audioMeter,
                menuBarHeight: menuBarHeight,
                recordingDuration: recorder.recordingDuration
            )
            .frame(width: 70)
            
            // Cancel button for notch recorder
            if whisperState.recordingState == .recording {
                Button(action: {
                    Task {
                        await whisperState.cancelRecording()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Cancel recording (ESC)")
                .accessibilityLabel("Cancel recording")
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.trailing, 8)
        .animation(.easeInOut(duration: 0.2), value: whisperState.recordingState)
    }
    
    var body: some View {
        Group {
            if windowManager.isVisible {
                HStack(spacing: 0) {
                    leftSection
                    centerSection
                    rightSection
                }
                .frame(height: menuBarHeight)
                .background(Color.black)
                .mask {
                    NotchShape(cornerRadius: 10)
                }
                .clipped()
                .onHover { hovering in
                    isHovering = hovering
                }
                .opacity(windowManager.isVisible ? 1 : 0)
            }
        }
    }
}
