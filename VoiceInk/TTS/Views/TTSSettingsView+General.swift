import SwiftUI

// MARK: - General Settings Section
extension TTSSettingsView {
    @ViewBuilder
    func generalSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            interfaceSettingsGroup()
            
            appearanceSettingsGroup()
            
            notificationsSettingsGroup()

            pocketVoiceSettingsGroup()
            
            cacheSettingsGroup()
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Interface Settings
    @ViewBuilder
    private func interfaceSettingsGroup() -> some View {
        GroupBox("Interface") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Tickwick Settings (Inspector)", isOn: $settings.isInspectorEnabled)
                
                Text("Show the advanced settings inspector in the Text-to-Speech workspace.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Appearance Settings
    @ViewBuilder
    private func appearanceSettingsGroup() -> some View {
        GroupBox("Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Appearance", selection: $settings.appearancePreference) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Appearance")

                Text("Override the system setting when you need a consistent light or dark presentation.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Toggle(isOn: $settings.isMinimalistMode) {
                    Text("Minimalist layout (Compact)")
                }
                .accessibilityLabel("Minimalist layout (Compact)")
                .accessibilityHint("Reduce chrome and move advanced controls to a popover. All functionality remains available.")
                
                Text("Reduces chrome and moves advanced controls to a popover. All functionality remains available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("Changes apply immediately and persist between launches.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Notifications Settings
    @ViewBuilder
    private func notificationsSettingsGroup() -> some View {
        GroupBox("Notifications") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { settings.setNotificationsEnabled($0) }
                )) {
                    Text("Notify when batch generation completes")
                }

                Text("Enables macOS alerts when batch queues finish processing. macOS will prompt for permission the first time you turn this on.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Pocket Voice Settings
    @ViewBuilder
    private func pocketVoiceSettingsGroup() -> some View {
        GroupBox("Pocket Voices") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hide Pocket voices you do not want to use. Hidden voices are removed from pickers and can be restored at any time.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if settings.hasHiddenPocketVoices {
                    ForEach(settings.sortedHiddenPocketVoiceIDs, id: \.self) { voiceID in
                        HStack {
                            Text(settings.pocketVoiceDisplayName(for: voiceID))
                                .font(.caption)
                            Spacer()
                            Button("Restore") {
                                settings.restorePocketVoice(withID: voiceID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Button("Restore All Hidden Pocket Voices") {
                        settings.restoreAllPocketVoices()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text("No Pocket voices are hidden.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Cache Settings
    @ViewBuilder
    private func cacheSettingsGroup() -> some View {
        GroupBox("Cache") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Audio cache helps speed up repeated generations.")
                    Spacer()
                }
                
                HStack {
                    Text("Cache size: ~0 MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear Cache") {
                        // Clear cache implementation
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}
