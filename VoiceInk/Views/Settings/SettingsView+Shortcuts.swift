import SwiftUI
import KeyboardShortcuts

// MARK: - Shortcuts Settings

extension SettingsView {
    var shortcutsSettings: some View {
        VStack(spacing: VoiceInkSpacing.md) {
            if sectionMatches("VoiceInk Shortcuts", in: .shortcuts) {
                VoiceInkSection(
                    icon: "command.circle",
                    title: "\(Localization.appName) Shortcuts",
                    subtitle: "Choose how you want to trigger \(Localization.appName)"
                ) {
                    VStack(alignment: .leading, spacing: 18) {
                        hotkeyView(
                            title: "Hotkey 1",
                            binding: $hotkeyManager.selectedHotkey1,
                            shortcutName: .toggleMiniRecorder
                        )

                        if hotkeyManager.selectedHotkey2 != .none {
                            Divider()
                            hotkeyView(
                                title: "Hotkey 2",
                                binding: $hotkeyManager.selectedHotkey2,
                                shortcutName: .toggleMiniRecorder2,
                                isRemovable: true,
                                onRemove: {
                                    withAnimation { hotkeyManager.selectedHotkey2 = .none }
                                }
                            )
                        }

                        if hotkeyManager.selectedHotkey1 != .none && hotkeyManager.selectedHotkey2 == .none {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation { hotkeyManager.selectedHotkey2 = .rightOption }
                                }) {
                                    Label("Add another hotkey", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                        }

                        Text("Quick tap to start hands-free recording (tap again to stop). Press and hold for push-to-talk (release to stop recording).")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            
            if sectionMatches("Other App Shortcuts", in: .shortcuts) {
                VoiceInkSection(
                icon: "keyboard.badge.ellipsis",
                title: "Other App Shortcuts",
                subtitle: "Additional shortcuts for \(Localization.appName)"
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    // Paste Last Transcript (Original)
                    HStack(spacing: 12) {
                        Text("Paste Last Transcript(Original)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        KeyboardShortcuts.Recorder(for: .pasteLastTranscription)
                            .controlSize(.small)
                        
                        InfoTip(
                            title: "Paste Last Transcript(Original)",
                            message: "Shortcut for pasting the most recent transcription."
                        )
                        
                        Spacer()
                    }

                    // Paste Last Transcript (Enhanced)
                    HStack(spacing: 12) {
                        Text("Paste Last Transcript(Enhanced)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        KeyboardShortcuts.Recorder(for: .pasteLastEnhancement)
                            .controlSize(.small)
                        
                        InfoTip(
                            title: "Paste Last Transcript(Enhanced)",
                            message: "Pastes the enhanced transcript if available, otherwise falls back to the original."
                        )
                        
                        Spacer()
                    }

                    // Retry Last Transcription
                    HStack(spacing: 12) {
                        Text("Retry Last Transcription")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)

                        KeyboardShortcuts.Recorder(for: .retryLastTranscription)
                            .controlSize(.small)

                        InfoTip(
                            title: "Retry Last Transcription",
                            message: "Re-transcribe the last recorded audio using the current model and copy the result."
                        )

                        Spacer()
                    }

                    Divider()
                    
                    // Custom Cancel Shortcut
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Toggle(isOn: $isCustomCancelEnabled.animation()) {
                                Text("Custom Cancel Shortcut")
                            }
                            .toggleStyle(.switch)
                            .onChange(of: isCustomCancelEnabled) { _, newValue in
                                if !newValue {
                                    KeyboardShortcuts.setShortcut(nil, for: .cancelRecorder)
                                }
                            }
                            
                            InfoTip(
                                title: "Dismiss Recording",
                                message: "Shortcut for cancelling the current recording session. Default: double-tap Escape."
                            )
                        }
                        
                        if isCustomCancelEnabled {
                            HStack(spacing: 12) {
                                Text("Cancel Shortcut")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                KeyboardShortcuts.Recorder(for: .cancelRecorder)
                                    .controlSize(.small)
                                
                                Spacer()
                            }
                            .padding(.leading, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    Divider()

                    // Middle-Click Toggle
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Toggle("Enable Middle-Click Toggle", isOn: $hotkeyManager.isMiddleClickToggleEnabled.animation())
                                .toggleStyle(.switch)
                            
                            InfoTip(
                                title: "Middle-Click Toggle",
                                message: "Use middle mouse button to toggle \(Localization.appName) recording."
                            )
                        }

                        if hotkeyManager.isMiddleClickToggleEnabled {
                            HStack(spacing: 8) {
                                Text("Activation Delay")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                TextField("", value: $hotkeyManager.middleClickActivationDelay, formatter: {
                                    let formatter = NumberFormatter()
                                    formatter.numberStyle = .none
                                    formatter.minimum = 0
                                    return formatter
                                }())
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(5)
                                .frame(width: 70)
                                
                                Text("ms")
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            .padding(.leading, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                }
            }
        }
    }
    
    @ViewBuilder
    func hotkeyView(
        title: String,
        binding: Binding<HotkeyManager.HotkeyOption>,
        shortcutName: KeyboardShortcuts.Name,
        isRemovable: Bool = false,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Menu {
                ForEach(HotkeyManager.HotkeyOption.allCases, id: \.self) { option in
                    Button(action: {
                        binding.wrappedValue = option
                    }) {
                        HStack {
                            Text(option.displayName)
                            if binding.wrappedValue == option {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(binding.wrappedValue.displayName)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            
            if binding.wrappedValue == .custom {
                KeyboardShortcuts.Recorder(for: shortcutName)
                    .controlSize(.small)
            }
            
            Spacer()
            
            if isRemovable {
                Button(action: {
                    onRemove?()
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}