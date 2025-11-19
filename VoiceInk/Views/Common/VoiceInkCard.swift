import SwiftUI

struct VoiceInkCard<Content: View>: View {
    var isSelected: Bool = false
    var padding: CGFloat = VoiceInkSpacing.lg
    var cornerRadius: CGFloat = VoiceInkRadius.medium
    let content: () -> Content

    init(isSelected: Bool = false,
         padding: CGFloat = VoiceInkSpacing.lg,
         cornerRadius: CGFloat = VoiceInkRadius.medium,
         @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            content()
        }
        .padding(padding)
        .voiceInkCardBackground(isSelected: isSelected, cornerRadius: cornerRadius)
        .shadow(color: VoiceInkTheme.Shadow.subtle, radius: 8, x: 0, y: 4)
    }
}
