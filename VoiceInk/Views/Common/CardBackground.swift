import SwiftUI

struct StyleConstants {
    static let cardGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(NSColor.controlBackgroundColor).opacity(0.5), location: 0.0),
            .init(color: Color(NSColor.controlBackgroundColor).opacity(0.3), location: 1.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cardGradientSelected = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color.accentColor.opacity(0.15), location: 0.0),
            .init(color: Color.accentColor.opacity(0.08), location: 1.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cardBorder = Color(NSColor.separatorColor).opacity(0.3)
    static let cardBorderSelected = Color.accentColor.opacity(0.3)
    
    static let shadowDefault = Color.black.opacity(0.03)
    static let shadowSelected = Color.black.opacity(0.06)
    
    static let cornerRadius: CGFloat = 12
}

struct CardBackground: View {
    var isSelected: Bool
    var cornerRadius: CGFloat = StyleConstants.cornerRadius
    var useAccentGradientWhenSelected: Bool = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        useAccentGradientWhenSelected && isSelected ?
                            StyleConstants.cardGradientSelected :
                            StyleConstants.cardGradient
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? StyleConstants.cardBorderSelected : StyleConstants.cardBorder,
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: isSelected ? StyleConstants.shadowSelected : StyleConstants.shadowDefault,
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 2 : 1
            )
    }
} 