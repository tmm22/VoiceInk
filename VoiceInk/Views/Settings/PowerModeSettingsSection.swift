import SwiftUI

struct PowerModeSettingsSection: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @AppStorage(AppSettings.Keys.powerModeUIFlag) private var powerModeUIFlag = false
    @AppStorage(PowerModeDefaults.autoRestoreKey) private var powerModeAutoRestoreEnabled = false
    @State private var showDisableAlert = false
    
    var body: some View {
        VoiceInkCard(isSelected: false) {
            HStack(spacing: VoiceInkSpacing.sm) {
                Image(systemName: "sparkles.square.fill.on.square")
                    .font(.system(size: 20))
                    .foregroundColor(VoiceInkTheme.Palette.accent)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Power Mode")
                        .voiceInkHeadline()
                    Text("Enable to automatically apply custom configurations based on the app or website you are using.")
                        .voiceInkSubheadline()
                }
                
                Spacer()
                
                Toggle("Enable Power Mode", isOn: toggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if powerModeUIFlag {
                Divider()
                    .padding(.vertical, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                
                HStack(spacing: 8) {
                    Toggle(isOn: $powerModeAutoRestoreEnabled) {
                        Text("Auto-Restore Preferences")
                    }
                    .toggleStyle(.switch)
                    
                    InfoTip(
                        title: "Auto-Restore Preferences",
                        message: "After each recording session, revert enhancement and transcription preferences to whatever was configured before Power Mode was activated."
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: powerModeUIFlag)
        .alert("Power Mode Still Active", isPresented: $showDisableAlert) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Power Mode can't be disabled while any configuration is still enabled. Disable or remove your Power Modes first.")
        }
    }
    
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { powerModeUIFlag },
            set: { newValue in
                if newValue {
                    powerModeUIFlag = true
                } else if powerModeManager.configurations.noneEnabled {
                    powerModeUIFlag = false
                } else {
                    showDisableAlert = true
                }
            }
        )
    }
    
}

private extension Array where Element == PowerModeConfig {
    var noneEnabled: Bool {
        allSatisfy { !$0.isEnabled }
    }
}

enum PowerModeDefaults {
    static let autoRestoreKey = AppSettings.Keys.powerModeAutoRestoreEnabled
}
