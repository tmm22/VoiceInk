import SwiftUI

struct VoiceInkDropZone<Accessory: View>: View {
    var isActive: Bool
    var icon: String = "arrow.down.doc"
    var title: String
    var subtitle: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil
    var accessory: () -> Accessory

    init(isActive: Bool,
         icon: String = "arrow.down.doc",
         title: String,
         subtitle: String,
         buttonTitle: String? = nil,
         buttonAction: (() -> Void)? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.isActive = isActive
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
        self.accessory = accessory
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: VoiceInkRadius.large, style: .continuous)
                .fill(VoiceInkTheme.Palette.surface.opacity(0.7))

            RoundedRectangle(cornerRadius: VoiceInkRadius.large, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isActive ? VoiceInkTheme.Palette.accent : VoiceInkTheme.Card.stroke)

            VStack(spacing: VoiceInkSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(isActive ? VoiceInkTheme.Palette.accent : .secondary)

                Text(title)
                    .voiceInkHeadline()

                Text(subtitle)
                    .voiceInkSubheadline()

                accessory()

                if let buttonTitle, let action = buttonAction {
                    Button(buttonTitle, action: action)
                        .buttonStyle(SecondaryBorderedButtonStyle())
                }
            }
            .padding(VoiceInkSpacing.xl)
        }
    }
}
