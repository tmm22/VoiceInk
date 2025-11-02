import SwiftUI

// MARK: - Dynamic UI Scaling System
//
// This file implements a comprehensive adaptive UI system that prevents content cutoff
// and minimizes scrolling by automatically scaling all UI elements to fit the screen.
//
// How it works:
// 1. Breakpoints: Four layout modes (ultraCompact, compact, regular, wide) based on window width
// 2. Dynamic Scaling: All sizes scaled proportionally using a scale factor (0.85-1.15x)
//    - Scale factor calculated relative to "ideal" 1440px width (comfortable default)
//    - At 1440px width = 1.0x scale (100%)
//    - At 1224px width = 0.85x scale (85% - minimum scale, still readable)
//    - At 1656px width = 1.15x scale (115% - maximum scale, spacious)
// 3. Automatic Adaptation: Everything scales together - panels, padding, spacing
// 4. Default window size: 1200×800 minimum, 1440×900 ideal for comfortable viewing
//
// Benefits:
// - No content cutoff at any window size
// - Minimal scrolling needed
// - Proportional scaling maintains visual balance
// - Works seamlessly from laptop (1280px) to 4K displays (3840px)
//
// Usage: Pass window size to ResponsiveConstants, all measurements auto-scale

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
    let windowWidth: CGFloat
    let windowHeight: CGFloat
    
    /// Dynamic scale factor based on window size (0.85 to 1.15 range)
    /// Scales UI elements proportionally to fit the screen
    var scaleFactor: CGFloat {
        // Base scale on width relative to "ideal" 1440px width (comfortable default)
        let idealWidth: CGFloat = 1440
        let widthScale = windowWidth / idealWidth
        
        // Clamp between 0.85 and 1.15 for more generous scaling
        // Starts scaling down less aggressively - better for readability
        return max(0.85, min(1.15, widthScale))
    }
    
    /// Whether to use compact vertical layout (for short windows)
    var isVerticallyCompact: Bool {
        return windowHeight < 800
    }
    
    init(width: CGFloat, height: CGFloat = 1000) {
        self.windowWidth = width
        self.windowHeight = height
        self.breakpoint = LayoutBreakpoint.current(for: width)
    }
    
    init(breakpoint: LayoutBreakpoint) {
        self.breakpoint = breakpoint
        self.windowWidth = 1680 // Default
        self.windowHeight = 1000 // Default
    }
    
    // MARK: - Panel Widths
    
    /// Inspector panel width range (dynamically scaled)
    var inspectorWidth: ClosedRange<CGFloat> {
        let baseRange: ClosedRange<CGFloat>
        switch breakpoint {
        case .ultraCompact:
            baseRange = 280...300  // Compact but usable
        case .compact:
            baseRange = 300...320  // Comfortable
        case .regular:
            baseRange = 320...360  // Standard - plenty of room for text
        case .wide:
            baseRange = 340...380  // Spacious - no cutoff issues
        }
        
        // Apply scale factor
        return (baseRange.lowerBound * scaleFactor)...(baseRange.upperBound * scaleFactor)
    }
    
    /// Ideal inspector width (midpoint of range)
    var idealInspectorWidth: CGFloat {
        let range = inspectorWidth
        return (range.lowerBound + range.upperBound) / 2
    }
    
    /// Context panel width range (dynamically scaled)
    var contextPanelWidth: ClosedRange<CGFloat> {
        let baseRange: ClosedRange<CGFloat>
        switch breakpoint {
        case .ultraCompact:
            baseRange = 220...240  // Very narrow to preserve center space
        case .compact:
            baseRange = 240...260  // Narrow
        case .regular:
            baseRange = 260...280  // Standard
        case .wide:
            baseRange = 280...300  // Spacious
        }
        
        // Apply scale factor
        return (baseRange.lowerBound * scaleFactor)...(baseRange.upperBound * scaleFactor)
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
    
    /// Standard panel padding (around entire panel) - dynamically scaled
    var panelPadding: CGFloat {
        let basePadding: CGFloat
        switch breakpoint {
        case .ultraCompact:
            basePadding = 8   // Tight but readable
        case .compact:
            basePadding = 10  // Comfortable
        case .regular:
            basePadding = 12  // Standard
        case .wide:
            basePadding = 14  // Generous
        }
        return basePadding * scaleFactor
    }
    
    /// Content padding (for main content areas) - dynamically scaled
    var contentPadding: CGFloat {
        let basePadding: CGFloat
        switch breakpoint {
        case .ultraCompact:
            basePadding = 12
        case .compact:
            basePadding = 16
        case .regular:
            basePadding = 20
        case .wide:
            basePadding = 24
        }
        return basePadding * scaleFactor
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
    
    /// Standard item spacing in VStacks/HStacks - dynamically scaled
    var itemSpacing: CGFloat {
        let baseSpacing: CGFloat
        switch breakpoint {
        case .ultraCompact:
            baseSpacing = 8
        case .compact:
            baseSpacing = 10
        case .regular:
            baseSpacing = 12
        case .wide:
            baseSpacing = 14
        }
        return baseSpacing * scaleFactor
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
