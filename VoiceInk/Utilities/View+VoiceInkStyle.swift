import SwiftUI

extension View {
    func voiceInkCardBackground(isSelected: Bool = false, cornerRadius: CGFloat = VoiceInkRadius.medium) -> some View {
        modifier(VoiceInkCardBackgroundModifier(isSelected: isSelected, cornerRadius: cornerRadius))
    }

    func voiceInkSectionPadding() -> some View {
        padding(VoiceInkSpacing.lg)
    }

    func voiceInkToolbarPadding() -> some View {
        padding(.horizontal, VoiceInkSpacing.md)
            .padding(.vertical, VoiceInkSpacing.xs)
    }
}

extension Text {
    func voiceInkHeadline() -> some View {
        font(VoiceInkTheme.Typography.title(size: 14, weight: .semibold))
    }

    func voiceInkSubheadline() -> some View {
        font(VoiceInkTheme.Typography.body(size: 12))
            .foregroundStyle(.secondary)
    }

    func voiceInkCaptionStyle() -> some View {
        font(VoiceInkTheme.Typography.caption())
            .foregroundStyle(.secondary)
    }
}

private struct VoiceInkCardBackgroundModifier: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VoiceInkTheme.Card.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(isSelected ? VoiceInkTheme.Card.selectedStroke : VoiceInkTheme.Card.stroke, lineWidth: 1)
                    )
            )
    }
}
