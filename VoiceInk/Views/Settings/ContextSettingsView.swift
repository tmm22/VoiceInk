import SwiftUI

struct ContextSettingsView: View {
    @Binding var settings: AIContextSettings
    
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
                
                VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                    contextToggle(
                        title: "Application Info",
                        isOn: $settings.includeApplicationContext,
                        description: "Shares the active application name and URL (if browser)."
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
            
            // MARK: - Personal Context Card
            VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.xs) {
                        HStack {
                            Text("Personal Context")
                                .voiceInkHeadline()
                            
                            InfoTip(
                                title: "Personal Context",
                                message: "This bio is sent with every request. Use it to define your role, preferred tone, or specific instructions."
                            )
                        }
                        
                        Text("Tell the AI who you are, your role, and your preferred writing style.")
                            .voiceInkCaptionStyle()
                    }
                    Spacer()
                }
                
                TextEditor(text: $settings.userBio)
                    .font(.body)
                    .frame(height: 100)
                    .padding(VoiceInkSpacing.sm)
                    .background(VoiceInkTheme.Palette.canvas)
                    .cornerRadius(VoiceInkRadius.small)
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.small)
                            .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if settings.userBio.isEmpty {
                                Text("Example: I am a software engineer. I prefer concise bullet points...")
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(VoiceInkSpacing.md)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
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
