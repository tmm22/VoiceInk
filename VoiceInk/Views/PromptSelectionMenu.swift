import SwiftUI

struct PromptSelectionMenu: View {
    @ObservedObject var enhancementService: AIEnhancementService
    
    var body: some View {
        Menu {
            ForEach(enhancementService.allPrompts) { prompt in
                Button {
                    enhancementService.setActivePrompt(prompt)
                } label: {
                    HStack {
                        Image(systemName: prompt.icon)
                            .foregroundColor(.accentColor)
                        Text(prompt.title)
                        if enhancementService.selectedPromptId == prompt.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text("Prompt: \(enhancementService.activePrompt?.title ?? "None")")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
            }
        }
        .disabled(!enhancementService.isEnhancementEnabled)
    }
}
