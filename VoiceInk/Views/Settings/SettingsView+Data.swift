import SwiftUI

// MARK: - Data Settings

extension SettingsView {
    var dataSettings: some View {
        VStack(spacing: VoiceInkSpacing.md) {
            if sectionMatches("Trash", in: .data) {
                VoiceInkSection(
                    icon: "trash",
                    title: Localization.Trash.title,
                    subtitle: "Recover deleted transcriptions"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deleted transcriptions are kept for 30 days before being permanently removed.")
                            .settingsDescription()
                        
                        HStack {
                            if trashItemCount > 0 {
                                Text(String(format: Localization.Trash.itemCount, trashItemCount))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(Localization.Trash.trashIsEmpty)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button {
                                showTrashView = true
                            } label: {
                                Label(Localization.Trash.openTrash, systemImage: "trash")
                            }
                            .controlSize(.large)
                        }
                    }
                }
                .onAppear {
                    updateTrashCount()
                }
            }
            
            if sectionMatches("Data & Privacy", in: .data) {
                VoiceInkSection(
                    icon: "lock.shield",
                    title: "Data & Privacy",
                    subtitle: "Control transcript history and storage"
                ) {
                    AudioCleanupSettingsView()
                }
            }
            
            if sectionMatches("Data Management", in: .data) {
                VoiceInkSection(
                    icon: "arrow.up.arrow.down.circle",
                    title: "Data Management",
                    subtitle: "Import or export your settings"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export your custom prompts, power modes, word replacements, keyboard shortcuts, and app preferences to a backup file. API keys are not included in the export.")
                            .settingsDescription()

                        HStack(spacing: 12) {
                            Button {
                                ImportExportService.shared.importSettings(
                                    enhancementService: enhancementService, 
                                    whisperPrompt: whisperState.whisperPrompt, 
                                    hotkeyManager: hotkeyManager, 
                                    menuBarManager: menuBarManager, 
                                    mediaController: MediaController.shared, 
                                    playbackController: PlaybackController.shared,
                                    soundManager: SoundManager.shared,
                                    whisperState: whisperState
                                )
                            } label: {
                                Label("Import Settings...", systemImage: "arrow.down.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)

                            Button {
                                ImportExportService.shared.exportSettings(
                                    enhancementService: enhancementService, 
                                    whisperPrompt: whisperState.whisperPrompt, 
                                    hotkeyManager: hotkeyManager, 
                                    menuBarManager: menuBarManager, 
                                    mediaController: MediaController.shared, 
                                    playbackController: PlaybackController.shared,
                                    soundManager: SoundManager.shared,
                                    whisperState: whisperState
                                )
                            } label: {
                                Label("Export Settings...", systemImage: "arrow.up.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                        }
                    }
                }
            }
        }
    }
}