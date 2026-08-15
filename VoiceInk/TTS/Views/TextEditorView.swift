import SwiftUI

struct TextEditorView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @FocusState private var isFocused: Bool
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background and border
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isFocused ? Color.accentColor.opacity(0.5) :
                            isHovering ? Color.secondary.opacity(0.3) :
                            Color.secondary.opacity(0.2),
                            lineWidth: isFocused ? (settings.isMinimalistMode ? 1.5 : 2) : 1
                        )
                )
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
                .animation(.easeInOut(duration: 0.1), value: isHovering)
            
            // Text Editor
            TextEditor(text: $viewModel.inputText)
                .font(.system(size: 14, weight: .regular, design: .default))
                .focused($isFocused)
                .frame(minHeight: settings.isMinimalistMode ? 220 : 260)
                .padding(settings.isMinimalistMode ? 6 : 8)
                .background(Color.clear)
                .scrollContentBackground(.hidden)
                .onChange(of: viewModel.inputText) { _, newValue in
                    let limit = settings.currentCharacterLimit
                    guard newValue.count > limit else { return }

                    if viewModel.shouldAllowCharacterOverflow(for: newValue) {
                        return
                    }

                    viewModel.inputText = String(newValue.prefix(limit))
                }
            
            // Placeholder text
            if viewModel.inputText.isEmpty {
                Text(Localization.TTS.editorPlaceholder)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 0,
               maxWidth: .infinity,
               minHeight: settings.isMinimalistMode ? 220 : 260,
               maxHeight: .infinity,
               alignment: .topLeading)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            // Auto-focus on appear
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                isFocused = true
            }
        }
        .contextMenu {
            // Context menu options
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viewModel.inputText, forType: .string)
            }) {
                Label(Localization.TTS.copyAll, systemImage: "doc.on.doc")
            }
            .disabled(viewModel.inputText.isEmpty)
            
            Button(action: {
                if let string = NSPasteboard.general.string(forType: .string) {
                    viewModel.inputText = string
                }
            }) {
                Label(Localization.TTS.paste, systemImage: "doc.on.clipboard")
            }
            
            Divider()
            
            Button(action: {
                viewModel.inputText = ""
            }) {
                Label(Localization.TTS.clear, systemImage: "trash")
            }
            .disabled(viewModel.inputText.isEmpty)
            
            Divider()
            
            Menu(Localization.TTS.insertSampleText) {
                Button(Localization.TTS.shortSample) {
                    viewModel.inputText = Localization.TTS.shortSampleText
                }
                
                Button(Localization.TTS.mediumSample) {
                    viewModel.inputText = Localization.TTS.mediumSampleText
                }
                
                Button(Localization.TTS.longSample) {
                    viewModel.inputText = Localization.TTS.longSampleText
                }
            }
        }
    }
}

// Text Editor Extensions for better functionality
extension TextEditorView {
    // Helper function to count words
    private func wordCount(_ text: String) -> Int {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }
    
    // Helper function to estimate reading time
    private func estimatedReadingTime(_ text: String) -> String {
        let words = wordCount(text)
        let wordsPerMinute = 150 // Average reading speed
        let minutes = Double(words) / Double(wordsPerMinute)
        
        if minutes < 1 {
            return "< 1 min"
        } else if minutes < 60 {
            return "\(Int(minutes)) min"
        } else {
            let hours = Int(minutes / 60)
            let remainingMinutes = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// Preview
struct TextEditorView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = TTSViewModel()
        TextEditorView()
            .environmentObject(viewModel)
            .environmentObject(viewModel.settings)
            .frame(width: 600, height: 400)
            .padding()
    }
}
