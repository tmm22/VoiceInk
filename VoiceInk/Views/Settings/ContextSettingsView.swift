import SwiftUI

struct ContextSettingsView: View {
    @Binding var settings: AIContextSettings
    
    // Derived state for the current level
    private var currentLevel: ContextAwarenessLevel? {
        for level in ContextAwarenessLevel.allCases {
            if settings.matchesLevel(level) {
                return level
            }
        }
        return nil // Custom
    }
    
    var body: some View {
        VStack(spacing: VoiceInkSpacing.lg) {
            // MARK: - Operational Context Card
            VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.xs) {
                        Text("Operational Context")
                            .voiceInkHeadline()
                        
                        Text("Choose what information is shared with the AI to improve transcription accuracy.")
                            .voiceInkCaptionStyle()
                    }
                    Spacer()
                }
                
                Divider()
                    .padding(.vertical, VoiceInkSpacing.xs)
                
                // Tiered Selection
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(ContextAwarenessLevel.allCases) { level in
                            let isSelected = currentLevel == level
                            Button {
                                withAnimation {
                                    settings.applyLevel(level)
                                    // Handle side effects like permissions
                                    if level == .maximum {
                                        Task { _ = await CalendarService.shared.requestAccess() }
                                    }
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(level.displayName)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                    Text(level.tradeOff)
                                        .font(.system(size: 9))
                                        .opacity(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? VoiceInkTheme.Palette.accent.opacity(0.15) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? VoiceInkTheme.Palette.accent : Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .foregroundColor(isSelected ? VoiceInkTheme.Palette.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if currentLevel == nil {
                        Text("Custom Configuration Active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Granular Toggles (Collapsible or just always shown)
                VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                    contextToggle(
                        title: "Application Info",
                        isOn: $settings.includeApplicationContext,
                        description: "Shares the active application name and URL (if browser)."
                    )
                    
                    contextToggle(
                        title: "Browser Page Content",
                        isOn: $settings.includeBrowserContent,
                        description: "Extracts text from the active web page for summarization."
                    )
                    
                    contextToggle(
                        title: "Input Field Info",
                        isOn: $settings.includeFocusedElement,
                        description: "Shares details about the active text field (e.g. \"Subject\", \"Search\")."
                    )
                    
                    contextToggle(
                        title: "Date & Time",
                        isOn: $settings.includeTemporalContext,
                        description: "Shares current date, time, and timezone."
                    )
                    
                    contextToggle(
                        title: "Selected Text",
                        isOn: $settings.includeSelectedText,
                        description: "Shares text you have selected in other apps."
                    )
                    
                    contextToggle(
                        title: "Selected Files",
                        isOn: $settings.includeSelectedFiles,
                        description: "Shares filenames of files selected in Finder."
                    )
                    
                    contextToggle(
                        title: "Calendar Events",
                        isOn: $settings.includeCalendar,
                        description: "Shares upcoming events for scheduling context."
                    )
                    .onChange(of: settings.includeCalendar) { oldValue, newValue in
                        if newValue {
                            Task {
                                _ = await CalendarService.shared.requestAccess()
                            }
                        }
                    }
                    
                    contextToggle(
                        title: "Clipboard Content",
                        isOn: $settings.includeClipboard,
                        description: "Shares your clipboard content."
                    )
                    
                    contextToggle(
                        title: "Screen Content (OCR)",
                        isOn: $settings.includeScreenCapture,
                        description: "Captures text from the active window to correct terms."
                    )
                }
            }
            .padding(VoiceInkSpacing.lg)
            .voiceInkCardBackground()
            
            // MARK: - Conversation History Card
            VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.xs) {
                        Text("Conversation History")
                            .voiceInkHeadline()
                        
                        Text("Allow the AI to see recent transcriptions to understand follow-up commands.")
                            .voiceInkCaptionStyle()
                    }
                    Spacer()
                    
                    Toggle("", isOn: $settings.includeConversationHistory)
                        .toggleStyle(SwitchToggleStyle(tint: VoiceInkTheme.Palette.accent))
                }
                
                if settings.includeConversationHistory {
                    Divider()
                        .padding(.vertical, VoiceInkSpacing.xs)
                    
                    VStack(spacing: VoiceInkSpacing.sm) {
                        HStack {
                            Text("Max Items")
                                .voiceInkSubheadline()
                            Spacer()
                            Stepper("\(settings.maxConversationItems)", value: $settings.maxConversationItems, in: 1...10)
                                .frame(width: 100)
                        }
                        
                        HStack {
                            Text("Time Window")
                                .voiceInkSubheadline()
                            Spacer()
                            Stepper("\(settings.conversationWindowMinutes) min", value: $settings.conversationWindowMinutes, in: 1...60)
                                .frame(width: 100)
                        }
                    }
                }
            }
            .padding(VoiceInkSpacing.lg)
            .voiceInkCardBackground()
        }
    }
    
    @ViewBuilder
    private func contextToggle(title: String, isOn: Binding<Bool>, description: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .voiceInkSubheadline()
                Text(description)
                    .voiceInkCaptionStyle()
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle(tint: VoiceInkTheme.Palette.accent))
        }
    }
}
