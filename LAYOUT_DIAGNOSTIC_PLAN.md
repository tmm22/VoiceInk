# Layout Diagnostic Plan: Preventing Content Cutoff Issues

## Problem Analysis
The inspector panel has content cutoff issues due to:
1. Fixed frame width (300px) at the container level
2. CardBackground with padding inside that reduces available space
3. Additional padding applied to content areas
4. No validation that content fits within allocated space

## Root Causes
- **Frame width constraint + nested padding = content overflow**
- **No frame introspection during development**
- **Inconsistent padding patterns across similar components**

## Comprehensive Solution Strategy

### 1. Immediate Fix (Current Issue)
**Problem:** Inspector has `.frame(width: 300)` but internal padding reduces actual content width to ~260px

**Solution:**
- Remove nested padding structure
- Apply padding only at the outermost level BEFORE background
- OR increase frame width to accommodate padding
- Ensure CardBackground is applied AFTER all content and padding

**Pattern to follow:**
```swift
VStack {
    // Content here
}
.padding(desiredPadding)  // Apply padding FIRST
.background(CardBackground())  // Background goes AFTER padding
.frame(width: totalWidth)  // Frame encompasses everything
```

### 2. Layout Constants System
Create a centralized layout constants file to ensure consistency:

**File: `VoiceInk/TTS/Views/Common/LayoutConstants.swift`**
```swift
struct LayoutConstants {
    // Panel widths
    static let contextPanelWidth: CGFloat = 300
    static let inspectorPanelWidth: CGFloat = 300
    static let contextRailWidth: CGFloat = 68
    
    // Content padding
    static let panelPadding: CGFloat = 20
    static let panelHeaderPadding: CGFloat = 20
    static let panelContentHorizontalPadding: CGFloat = 20
    static let panelContentBottomPadding: CGFloat = 20
    
    // Calculated effective widths
    static let contextPanelContentWidth: CGFloat = contextPanelWidth - (panelPadding * 2)
    static let inspectorPanelContentWidth: CGFloat = inspectorPanelWidth - (panelPadding * 2)
    
    // Minimum widths for safety
    static let minCardContentWidth: CGFloat = 240
    
    // Helper to validate layout
    static func validateContentFits(
        containerWidth: CGFloat,
        padding: CGFloat,
        minimumContentWidth: CGFloat
    ) -> Bool {
        let availableWidth = containerWidth - (padding * 2)
        return availableWidth >= minimumContentWidth
    }
}
```

### 3. Automated Layout Validation
Add compile-time and runtime checks:

**A. Compile-time static assertions (in constants file):**
```swift
extension LayoutConstants {
    static func assertLayoutValid() {
        assert(
            validateContentFits(
                containerWidth: inspectorPanelWidth,
                padding: panelPadding,
                minimumContentWidth: minCardContentWidth
            ),
            "Inspector panel too narrow for content with padding"
        )
        
        assert(
            validateContentFits(
                containerWidth: contextPanelWidth,
                padding: panelPadding,
                minimumContentWidth: minCardContentWidth
            ),
            "Context panel too narrow for content with padding"
        )
    }
}
```

**B. Runtime debug overlay (development only):**
```swift
#if DEBUG
struct LayoutDebugOverlay: ViewModifier {
    let label: String
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    VStack(alignment: .leading) {
                        Text("\(label)")
                            .font(.caption2)
                        Text("W: \(Int(geometry.size.width))")
                            .font(.caption2)
                        Text("H: \(Int(geometry.size.height))")
                            .font(.caption2)
                    }
                    .padding(4)
                    .background(Color.red.opacity(0.7))
                    .foregroundColor(.white)
                    .font(.system(size: 10, design: .monospaced))
                    .allowsHitTesting(false)
                }
            )
    }
}

extension View {
    func debugLayout(_ label: String) -> some View {
        self.modifier(LayoutDebugOverlay(label: label))
    }
}
#endif
```

### 4. Standard Component Patterns

**Pattern A: Panel with CardBackground**
```swift
// CORRECT: Padding inside, background wraps everything
VStack {
    // Header
    VStack {
        // Header content
    }
    .padding(LayoutConstants.panelHeaderPadding)
    
    // Scrollable content
    ScrollView {
        VStack {
            // Content
        }
        .padding(.horizontal, LayoutConstants.panelContentHorizontalPadding)
        .padding(.bottom, LayoutConstants.panelContentBottomPadding)
    }
}
.background(CardBackground())
.frame(width: LayoutConstants.inspectorPanelWidth)
```

**Pattern B: Panel without CardBackground**
```swift
// For panels that don't need card styling
VStack {
    // Content
}
.padding(LayoutConstants.panelPadding)
.frame(width: LayoutConstants.contextPanelWidth)
```

### 5. Pre-commit Checklist
Add to CONTRIBUTING.md:

**Layout Changes Checklist:**
- [ ] Used LayoutConstants for all widths and padding
- [ ] Applied padding BEFORE background modifiers
- [ ] Frame widths account for internal padding
- [ ] Tested at minimum window size
- [ ] Verified ScrollView content is not cut off
- [ ] No fixed heights on scrollable content
- [ ] Checked in both light and dark mode
- [ ] Verified with longest expected content

### 6. Automated Testing (Future Enhancement)
Create snapshot tests for layout:
```swift
func testInspectorPanelLayout() {
    let inspector = InspectorPanelView(...)
        .frame(width: 300, height: 600)
    
    // Assert no clipping
    assertNoClipping(inspector)
    
    // Assert minimum content width
    assertMinimumWidth(inspector, min: LayoutConstants.minCardContentWidth)
    
    // Snapshot test
    assertSnapshot(matching: inspector, as: .image)
}
```

### 7. Code Review Guidelines
When reviewing layout changes:
1. Check frame widths vs content padding
2. Verify CardBackground is outermost modifier
3. Ensure ScrollView has proper bounds
4. Test with maximum expected content
5. Verify no hardcoded magic numbers

### 8. Documentation Standard
Add inline documentation to layout code:
```swift
// Layout: 300px total width
// - 20px padding left
// - 260px content area
// - 20px padding right
.frame(width: 300)
```

## Implementation Priority
1. ✅ Fix current inspector cutoff issue (IMMEDIATE)
2. ⬜ Create LayoutConstants.swift (HIGH)
3. ⬜ Refactor all panels to use constants (HIGH)
4. ⬜ Add debug overlay mode (MEDIUM)
5. ⬜ Add validation assertions (MEDIUM)
6. ⬜ Update documentation (LOW)
7. ⬜ Add snapshot tests (LOW)

## Success Metrics
- Zero content cutoff issues reported
- All panels use LayoutConstants
- Debug mode shows no layout warnings
- Consistent padding across all panels
- Layout changes pass automated checks
