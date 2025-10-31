import SwiftUI

struct StyleConstants {
    static let cardBorder = Color.primary.opacity(0.08)
    static let cardBorderSelected = Color.accentColor.opacity(0.4)
    static let cornerRadius: CGFloat = 6
}

struct CardBackground: View {
    var isSelected: Bool
    var cornerRadius: CGFloat = StyleConstants.cornerRadius
    var useAccentGradientWhenSelected: Bool = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? StyleConstants.cardBorderSelected : StyleConstants.cardBorder,
                        lineWidth: 1
                    )
            )
    }
} 