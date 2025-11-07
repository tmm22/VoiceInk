import SwiftUI
import KeyboardShortcuts

struct KeyboardShortcutCheatSheet: View {
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Recording Section
                    ShortcutSection(title: "Recording", icon: "mic.fill", iconColor: .red) {
                        ShortcutRow(
                            action: "Start/Stop Recording",
                            shortcut: hotkeyManager.selectedHotkey1.displayName,
                            description: "Quick tap to toggle hands-free mode, hold for push-to-talk"
                        )
                        
                        if hotkeyManager.selectedHotkey2 != .none {
                            ShortcutRow(
                                action: "Alternative Recording Trigger",
                                shortcut: hotkeyManager.selectedHotkey2.displayName,
                                description: "Secondary hotkey option"
                            )
                        }
                        
                        ShortcutRow(
                            action: "Cancel Recording",
                            shortcut: "ESC ESC",
                            description: "Double-tap Escape to cancel current recording"
                        )
                        
                        if let customCancel = KeyboardShortcuts.getShortcut(for: .cancelRecorder) {
                            ShortcutRow(
                                action: "Cancel (Custom)",
                                shortcut: customCancel.description,
                                description: "Custom cancel shortcut"
                            )
                        }
                        
                        if hotkeyManager.isMiddleClickToggleEnabled {
                            ShortcutRow(
                                action: "Middle-Click Toggle",
                                shortcut: "Middle Mouse",
                                description: "Use middle mouse button to toggle recording"
                            )
                        }
                    }
                    
                    // Paste Section
                    ShortcutSection(title: "Paste Transcriptions", icon: "doc.on.clipboard", iconColor: .blue) {
                        if let shortcut = KeyboardShortcuts.getShortcut(for: .pasteLastTranscription) {
                            ShortcutRow(
                                action: "Paste Last Transcript (Original)",
                                shortcut: shortcut.description,
                                description: "Paste the most recent unprocessed transcription"
                            )
                        }
                        
                        if let shortcut = KeyboardShortcuts.getShortcut(for: .pasteLastEnhancement) {
                            ShortcutRow(
                                action: "Paste Last Transcript (Enhanced)",
                                shortcut: shortcut.description,
                                description: "Paste enhanced transcript, fallback to original if unavailable"
                            )
                        }
                        
                        if let shortcut = KeyboardShortcuts.getShortcut(for: .retryLastTranscription) {
                            ShortcutRow(
                                action: "Retry Last Transcription",
                                shortcut: shortcut.description,
                                description: "Re-transcribe the last audio with current model"
                            )
                        }
                    }
                    
                    // History Section
                    ShortcutSection(title: "History Navigation", icon: "clock.arrow.circlepath", iconColor: .purple) {
                        ShortcutRow(
                            action: "Search History",
                            shortcut: "⌘F",
                            description: "Focus the search field in History view"
                        )
                        
                        ShortcutRow(
                            action: "Delete Selected",
                            shortcut: "⌫",
                            description: "Delete selected transcription entries"
                        )
                        
                        ShortcutRow(
                            action: "Select All",
                            shortcut: "⌘A",
                            description: "Select all transcriptions in current view"
                        )
                    }
                    
                    // General Section
                    ShortcutSection(title: "General", icon: "command", iconColor: .gray) {
                        ShortcutRow(
                            action: "Show This Help",
                            shortcut: "⌘?",
                            description: "Display keyboard shortcuts reference"
                        )
                        
                        ShortcutRow(
                            action: "Open Settings",
                            shortcut: "⌘,",
                            description: "Open application settings"
                        )
                        
                        ShortcutRow(
                            action: "Close Window",
                            shortcut: "⌘W",
                            description: "Close current window"
                        )
                        
                        ShortcutRow(
                            action: "Quit VoiceLink",
                            shortcut: "⌘Q",
                            description: "Exit the application"
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("Customize shortcuts in Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Open Settings") {
                    dismiss()
                    NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Settings"])
                }
                .controlSize(.small)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ShortcutSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let content: Content
    
    init(title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

struct ShortcutRow: View {
    let action: String
    let shortcut: String
    let description: String?
    
    init(action: String, shortcut: String, description: String? = nil) {
        self.action = action
        self.shortcut = shortcut
        self.description = description
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action)
                    .font(.system(size: 13, weight: .medium))
                
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    KeyboardShortcutCheatSheet()
        .environmentObject(HotkeyManager(whisperState: WhisperState(modelContext: ModelContext(try! ModelContainer(for: Transcription.self)))))
}
