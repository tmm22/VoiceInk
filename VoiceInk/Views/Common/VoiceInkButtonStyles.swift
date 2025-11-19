import SwiftUI

struct PrimaryProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, VoiceInkSpacing.lg)
            .padding(.vertical, VoiceInkSpacing.sm)
            .background(VoiceInkTheme.Palette.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: VoiceInkRadius.medium, style: .continuous))
            .shadow(color: VoiceInkTheme.Shadow.subtle.opacity(configuration.isPressed ? 0.2 : 0.35), radius: 8, x: 0, y: 4)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryBorderedButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, VoiceInkSpacing.lg)
            .padding(.vertical, VoiceInkSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: VoiceInkRadius.medium, style: .continuous)
                    .fill(VoiceInkTheme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VoiceInkRadius.medium, style: .continuous)
                    .stroke(VoiceInkTheme.Card.stroke, lineWidth: 1)
            )
            .foregroundColor(tint)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
