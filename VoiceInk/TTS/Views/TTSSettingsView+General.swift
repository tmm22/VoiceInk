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
