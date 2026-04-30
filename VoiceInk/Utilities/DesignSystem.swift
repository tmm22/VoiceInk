import SwiftUI

enum VoiceInkSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum VoiceInkRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
}

enum VoiceInkTheme {
    enum Palette {
        static let canvas = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let elevatedSurface = Color(nsColor: .underPageBackgroundColor)
        static let outline = Color(nsColor: .separatorColor).opacity(0.7)
        static let outlineStrong = Color(nsColor: .separatorColor)
        static let muted = Color.primary.opacity(0.05)
        static let accent = Color.accentColor
        static let warning = Color(nsColor: .systemOrange)
    }

    enum Card {
        static let background = Palette.surface
        static let stroke = Palette.outline
        static let selectedStroke = Palette.accent.opacity(0.4)
        static let hoverFill = Palette.muted
    }

    enum Shadow {
        static let subtle = Color.black.opacity(0.04)
    }

    enum Sidebar {
        static let backgroundMaterial: NSVisualEffectView.Material = .underWindowBackground
        static let hoverOpacity: Double = 0.05
        static let selectedOpacity: Double = 0.12
    }

    enum Typography {
        static func title(size: CGFloat = 13, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight)
        }

        static func body(size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }

        static func caption(size: CGFloat = 11) -> Font {
            .system(size: size)
        }
    }
}
