import SwiftUI

struct VoiceInkSection<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var showWarning: Bool = false
    let content: () -> Content

    init(icon: String,
         title: String,
         subtitle: String,
         showWarning: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showWarning = showWarning
        self.content = content
    }

    var body: some View {
        VoiceInkCard(isSelected: showWarning) {
            HStack(spacing: VoiceInkSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(showWarning ? Color.red : .secondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: VoiceInkSpacing.xxs) {
                    Text(title)
                        .voiceInkHeadline()
                    Text(subtitle)
                        .voiceInkCaptionStyle()
                }

                Spacer()

                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .help("Permission required for VoiceInk to function properly")
                }
            }

            Divider()

            content()
        }
    }
}
