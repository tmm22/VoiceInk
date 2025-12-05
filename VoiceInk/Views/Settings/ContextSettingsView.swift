import SwiftUI

struct ContextSettingsView: View {
    @Binding var settings: AIContextSettings
    
    var body: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Operational Context")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Text("Choose what information is shared with the AI to improve transcription accuracy.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Include application info", isOn: $settings.includeApplicationContext)
                            .help("Shares the active application name and URL (if browser) to understand context.")
                        
                        Toggle("Include input field info", isOn: $settings.includeFocusedElement)
                            .help("Shares details about the text field you are typing in (e.g. \"Subject Line\", \"Search\").")
                        
                        Toggle("Include date and time", isOn: $settings.includeTemporalContext)
                            .help("Shares current date, time, and timezone for scheduling accuracy.")
                        
                        Toggle("Include selected text", isOn: $settings.includeSelectedText)
                            .help("Shares text you have selected in other apps.")
                        
                        Toggle("Include clipboard content", isOn: $settings.includeClipboard)
                            .help("Shares your clipboard content.")
                        
                        Toggle("Include screen content (OCR)", isOn: $settings.includeScreenCapture)
                            .help("Captures text from the active window to correct terms and names.")
                    }
                }
                .padding(8)
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Conversation History")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Toggle("Include recent transcriptions", isOn: $settings.includeConversationHistory)
                        .help("Shares recent transcriptions to maintain conversation context.")
                    
                    if settings.includeConversationHistory {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Max items: \(settings.maxConversationItems)")
                                Stepper("", value: $settings.maxConversationItems, in: 1...10)
                            }
                            
                            HStack {
                                Text("Window: \(settings.conversationWindowMinutes) min")
                                Stepper("", value: $settings.conversationWindowMinutes, in: 1...60)
                            }
                        }
                        .padding(.leading, 20)
                        
                        Text("Sharing recent transcriptions helps the AI understand follow-up commands.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Personal Context")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Text("Tell the AI who you are, your role, and your preferred writing style.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $settings.userBio)
                        .font(.body)
                        .frame(height: 100)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .help("Example: I am a software engineer. I prefer concise bullet points. I often use technical jargon like API, JSON, and Swift.")
                }
                .padding(8)
            }
        }
    }
}
