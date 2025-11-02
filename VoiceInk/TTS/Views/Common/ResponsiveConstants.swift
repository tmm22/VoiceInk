import SwiftUI

/// Defines the responsive layout breakpoints for the application
enum LayoutBreakpoint: String, CaseIterable {
    case ultraCompact  // < 960px
    case compact       // 960-1279px
    case regular       // 1280-1679px
    case wide          // >= 1680px
    
    /// Determines the current breakpoint based on available width
    static func current(for width: CGFloat) -> LayoutBreakpoint {
        switch width {
        case ..<960:
            return .ultraCompact
        case 960..<1280:
            return .compact
        case 1280..<1680:
            return .regular
        default:
            return .wide
        }
    }
    
    var displayName: String {
        switch self {
        case .ultraCompact: return "Ultra Compact"
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .wide: return "Wide"
        }
    }
}

/// Provides responsive sizing constants based on the current layout breakpoint
struct ResponsiveConstants {
    let breakpoint: LayoutBreakpoint
    
    init(width: CGFloat) {
        self.breakpoint = LayoutBreakpoint.current(for: width)
    }
    
    init(breakpoint: LayoutBreakpoint) {
        self.breakpoint = breakpoint
    }
    
    // MARK: - Panel Widths
    
    /// Inspector panel width range
    var inspectorWidth: ClosedRange<CGFloat> {
        switch breakpoint {
        case .ultraCompact:
            return 260...280  // Very compact for limited space
        case .compact:
            return 270...290  // Still compact
        case .regular:
            return 290...320  // More breathing room
        case .wide:
            return 310...350  // Full featured
        }
    }
    
    /// Ideal inspector width (midpoint of range)
    var idealInspectorWidth: CGFloat {
        let range = inspectorWidth
        return (range.lowerBound + range.upperBound) / 2
    }
    
    /// Context panel width range
    var contextPanelWidth: ClosedRange<CGFloat> {
        switch breakpoint {
        case .ultraCompact:
            return 220...240  // Very narrow to preserve center space
        case .compact:
            return 240...260  // Narrow
        case .regular:
            return 260...280  // Standard
        case .wide:
            return 280...300  // Spacious
        }
    }
    
    /// Ideal context panel width (midpoint of range)
    var idealContextPanelWidth: CGFloat {
        let range = contextPanelWidth
        return (range.lowerBound + range.upperBound) / 2
    }
    
    /// Context rail width (icon bar on the left)
    var contextRailWidth: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 60  // Narrower
        case .compact:
            return 64
        case .regular:
            return 68
        case .wide:
            return 72  // More generous
        }
    }
    
    // MARK: - Padding
    
    /// Standard panel padding (around entire panel)
    var panelPadding: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 6   // Very tight
        case .compact:
            return 8   // Tight
        case .regular:
            return 10  // Comfortable
        case .wide:
            return 12  // Generous
        }
    }
    
    /// Content padding (for main content areas)
    var contentPadding: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 12
        case .compact:
            return 16
        case .regular:
            return 20
        case .wide:
            return 24
        }
    }
    
    /// Horizontal padding for composer and main areas
    var composerHorizontalPadding: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 12
        case .compact:
            return 16
        case .regular:
            return 20
        case .wide:
            return 28
        }
    }
    
    /// Vertical padding for composer
    var composerVerticalPadding: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 12
        case .compact:
            return 16
        case .regular:
            return 20
        case .wide:
            return 24
        }
    }
    
    /// Command strip vertical padding
    var commandStripVerticalPadding: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 8
        case .compact:
            return 10
        case .regular:
            return 12
        case .wide:
            return 14
        }
    }
    
    // MARK: - Spacing
    
    /// Standard item spacing in VStacks/HStacks
    var itemSpacing: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 8
        case .compact:
            return 10
        case .regular:
            return 12
        case .wide:
            return 14
        }
    }
    
    /// Card spacing
    var cardSpacing: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 12
        case .compact:
            return 14
        case .regular:
            return 16
        case .wide:
            return 18
        }
    }
    
    // MARK: - Font Sizes
    
    /// Dynamic headline font size
    var headlineFontSize: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 14
        case .compact:
            return 15
        case .regular:
            return 17
        case .wide:
            return 18
        }
    }
    
    /// Dynamic body font size
    var bodyFontSize: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 12
        case .compact:
            return 13
        case .regular:
            return 14
        case .wide:
            return 14
        }
    }
    
    /// Dynamic caption font size
    var captionFontSize: CGFloat {
        switch breakpoint {
        case .ultraCompact:
            return 10
        case .compact:
            return 11
        case .regular:
            return 12
        case .wide:
            return 12
        }
    }
    
    // MARK: - Minimum Sizes
    
    /// Minimum supported window width
    static let minimumWindowWidth: CGFloat = 960
    
    /// Minimum supported window height
    static let minimumWindowHeight: CGFloat = 600
    
    /// Minimum timeline width for playback bar
    var minimumTimelineWidth: CGFloat {
        return 200
    }
    
    // MARK: - Helper Methods
    
    /// Calculate available width for center composer area
    func composerWidth(totalWidth: CGFloat, 
                       contextPanelVisible: Bool,
                       inspectorVisible: Bool) -> CGFloat {
        var available = totalWidth
        
        // Subtract context rail if visible
        if contextPanelVisible {
            available -= contextRailWidth
            available -= idealContextPanelWidth
            available -= 2  // Dividers
        }
        
        // Subtract inspector if visible
        if inspectorVisible {
            available -= idealInspectorWidth
            available -= 1  // Divider
        }
        
        return max(400, available)  // Ensure minimum composer width
    }
    
    /// Check if current window size is below minimum
    static func isBelowMinimum(width: CGFloat, height: CGFloat) -> Bool {
        return width < minimumWindowWidth || height < minimumWindowHeight
    }
}

// MARK: - View Extension

extension View {
    /// Apply responsive padding based on current breakpoint
    func responsivePadding(_ constants: ResponsiveConstants) -> some View {
        self.padding(constants.panelPadding)
    }
    
    /// Apply responsive content padding
    func responsiveContentPadding(_ constants: ResponsiveConstants) -> some View {
        self.padding(constants.contentPadding)
    }
}
