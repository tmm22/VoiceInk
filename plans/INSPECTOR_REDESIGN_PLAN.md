# Inspector Redesign Plan

## Current Issues

### Problems with Current Design
1. **Long text strings** - "Notify me when batch generation completes" + long descriptions
2. **Fixed-width sections** - Don't adapt well to narrow panels
3. **Horizontal layout challenges** - Buttons and toggles can overflow
4. **Verbose labels** - Take up too much space
5. **No graceful degradation** - Content just gets cut off

### Root Causes
- Text-heavy UI relies on horizontal space
- No consideration for minimum viable width
- Labels and descriptions compete for same space
- No information hierarchy (everything same importance)

## Redesign Principles

### 1. **Vertical-First Design**
Stack everything vertically so width doesn't matter

### 2. **Progressive Disclosure**
Show essentials first, details on demand

### 3. **Icon-Heavy**
Use icons with tooltips instead of long labels

### 4. **Compact Language**
Shorter, clearer text

### 5. **Guaranteed Minimum Width**
Design for 240px minimum (will scale up)

## Proposed Redesign

### New Inspector Layout

```
┌─────────────────────────────┐
│ [Icon] Section Name      [x]│  ← Compact header
├─────────────────────────────┤
│ [■■■] Tab1  Tab2  Tab3  Tab4│  ← Icon-based tabs
├─────────────────────────────┤
│                             │
│  Content Area               │  ← Vertically stacked
│  (Scrollable)               │
│                             │
│  [Primary Action]           │  ← Full-width button
│                             │
└─────────────────────────────┘
```

### Specific Section Redesigns

#### Cost Inspector (Current → New)

**Current (Verbose):**
```
Estimated cost
$0.045
This estimate is based on OpenAI's current pricing...
[Refresh estimate]
```

**New (Compact):**
```
💰 Cost
$0.045 per generation

ℹ️ Based on current provider pricing
⟳ Refresh
```

#### Notifications Inspector (Current → New)

**Current (Long text):**
```
Batch alerts
☐ Notify me when batch generation completes
Notifications use the macOS alert center. You will only 
be notified for batches with at least one generated segment.
```

**New (Compact with tooltips):**
```
🔔 Batch Alerts

☐ Completion notifications  [ℹ️]

Tooltip: "Get notified when batch jobs finish.
Uses macOS notification center."
```

#### Provider Inspector (Current → New)

**Current (Verbose):**
```
OpenAI
OpenAI's text-to-speech service offers high-quality...
Supported export formats: MP3, WAV, FLAC, AAC
Using the provider default voice. Choose a voice from 
the Command strip to override.
```

**New (Compact with sections):**
```
[OpenAI icon] OpenAI

Quality: High
Formats: MP3, WAV, FLAC, AAC
Voice: Default [Change]

ℹ️ Tap for provider details
```

#### Transcript Inspector (Current → New)

**Current:**
```
Transcript export
Generate speech to create a transcript you can export as 
SRT or VTT.

[Export SRT] [Export VTT]
```

**New:**
```
📄 Transcript

Status: Not generated
Generate audio first to export captions.

Export Format:
[▼ SRT] [Export]
```

## Implementation Strategy

### Phase 1: Refactor Inspector Content Components

Create new, compact versions:
```swift
// New compact design pattern
private struct CompactInspectorRow: View {
    let icon: String
    let title: String
    let value: String?
    let action: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let value = value {
                    Text(value)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let action = action {
                Button(action: action) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

### Phase 2: Create InfoButton Component

For long descriptions:
```swift
private struct InfoButton: View {
    let message: String
    @State private var showingPopover = false
    
    var body: some View {
        Button {
            showingPopover = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover) {
            Text(message)
                .padding()
                .frame(maxWidth: 250)
        }
    }
}
```

### Phase 3: Implement Compact Sections

#### Cost Inspector - Redesigned
```swift
private struct CostInspectorContent: View {
    @EnvironmentObject var viewModel: TTSViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Cost display
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.costEstimate.summary)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("per generation")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                InfoButton(message: viewModel.costEstimate.detail ?? 
                          "Based on current provider pricing")
            }
            
            Divider()
            
            // Actions
            Button {
                viewModel.objectWillChange.send()
            } label: {
                Label("Refresh Estimate", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.inputText.isEmpty)
        }
    }
}
```

#### Notifications Inspector - Redesigned
```swift
private struct NotificationsInspectorContent: View {
    @EnvironmentObject var viewModel: TTSViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                Text("Batch Alerts")
                    .font(.headline)
                
                Spacer()
            }
            
            Toggle(isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { viewModel.setNotificationsEnabled($0) }
            )) {
                HStack(spacing: 4) {
                    Text("Completion notifications")
                        .font(.subheadline)
                    
                    InfoButton(message: "Get notified when batch generation completes. Uses macOS notification center.")
                }
            }
            
            if viewModel.notificationsEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Notifications enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
```

#### Provider Inspector - Redesigned
```swift
private struct ProviderInspectorContent: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var showingDetails = false
    
    var body: some View {
        let provider = viewModel.selectedProvider
        let profile = ProviderCostProfile.profile(for: provider)
        let formats = viewModel.supportedFormats.map(\.displayName).joined(separator: ", ")
        
        VStack(alignment: .leading, spacing: 16) {
            // Provider header
            HStack(spacing: 12) {
                Image(systemName: provider.icon)
                    .font(.title)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.headline)
                    
                    Text("Current Provider")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    showingDetails.toggle()
                } label: {
                    Image(systemName: showingDetails ? "chevron.up" : "info.circle")
                }
                .buttonStyle(.plain)
            }
            
            // Key info
            CompactInfoGrid(items: [
                ("waveform", "Quality", "High"),
                ("arrow.down.circle", "Formats", formats.components(separatedBy: ", ").first ?? "MP3"),
                ("person.wave.2", "Voice", viewModel.selectedVoice?.name ?? "Default")
            ])
            
            // Expanded details
            if showingDetails {
                Text(profile.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Voice selection hint
            if viewModel.selectedVoice == nil {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb")
                        .foregroundColor(.yellow)
                    Text("Choose voice from Command Strip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
}

private struct CompactInfoGrid: View {
    let items: [(icon: String, label: String, value: String)]
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: items[index].icon)
                        .frame(width: 20)
                        .foregroundColor(.secondary)
                    
                    Text(items[index].label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(items[index].value)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
```

#### Transcript Inspector - Redesigned
```swift
private struct TranscriptInspectorContent: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var selectedFormat: TranscriptFormat = .srt
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status
            HStack(spacing: 12) {
                Image(systemName: viewModel.currentTranscript != nil ? 
                      "doc.text.fill" : "doc.text")
                    .font(.title2)
                    .foregroundColor(viewModel.currentTranscript != nil ? 
                                   .green : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcript")
                        .font(.headline)
                    
                    Text(viewModel.currentTranscript != nil ? 
                         "Ready to export" : "Generate audio first")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if viewModel.currentTranscript != nil {
                Divider()
                
                // Format picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Format")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Picker("Format", selection: $selectedFormat) {
                        Label("SRT", systemImage: "captions.bubble")
                            .tag(TranscriptFormat.srt)
                        Label("VTT", systemImage: "text.bubble")
                            .tag(TranscriptFormat.vtt)
                    }
                    .pickerStyle(.segmented)
                }
                
                // Export button
                Button {
                    viewModel.exportTranscript(format: selectedFormat)
                } label: {
                    Label("Export Transcript", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Help text
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Generate speech to create transcript")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
}
```

## Key Design Patterns

### 1. Icon + Text Pattern
```swift
HStack(spacing: 8) {
    Image(systemName: icon)
        .frame(width: 20)
    Text(label)
    Spacer()
    Text(value)
}
```

### 2. Collapsible Details
```swift
@State private var expanded = false

Button { expanded.toggle() } label: {
    HStack {
        Text(title)
        Spacer()
        Image(systemName: expanded ? "chevron.up" : "chevron.down")
    }
}

if expanded {
    Text(details)
}
```

### 3. Info Popovers
```swift
Button {
    showInfo = true
} label: {
    Image(systemName: "info.circle")
}
.popover(isPresented: $showInfo) {
    Text(helpText).padding()
}
```

### 4. Status Indicators
```swift
HStack {
    Image(systemName: icon)
        .foregroundColor(statusColor)
    Text(statusText)
}
```

## Benefits of Redesign

### 1. Width-Independent ✅
- Vertical layout works at any width
- Minimum 240px vs current 300px+ requirement

### 2. Scannable ✅
- Icons provide quick visual reference
- Information hierarchy clear
- Less reading required

### 3. Progressive Disclosure ✅
- Essential info visible
- Details available on demand
- Less overwhelming

### 4. Touch-Friendly ✅
- Larger tap targets
- Full-width buttons
- Better for trackpad/mouse

### 5. Maintainable ✅
- Reusable components
- Consistent patterns
- Easier to add new sections

## Migration Strategy

### Step 1: Create New Components
- InfoButton
- CompactInspectorRow
- CompactInfoGrid
- StatusBadge

### Step 2: Redesign One Section at a Time
1. Cost (simplest)
2. Transcript (medium)
3. Notifications (medium)
4. Provider (most complex)

### Step 3: Test & Iterate
- Test at 240px, 300px, 360px widths
- Verify all interactions work
- Ensure no cutoff at any size

### Step 4: Apply Design System
- Document patterns in style guide
- Create templates for future sections
- Establish design review process

## Success Metrics

- ✅ No content cutoff at 240px minimum width
- ✅ All text readable without scrolling horizontally
- ✅ All buttons accessible and clickable
- ✅ Visual hierarchy clear at all sizes
- ✅ Less than 3 seconds to find any setting

## Future Enhancements

1. **Customizable Inspector**
   - Rearrange sections
   - Show/hide sections
   - Pin favorites

2. **Quick Actions**
   - Right-click context menus
   - Keyboard shortcuts for sections
   - Command palette integration

3. **Smart Defaults**
   - Remember last used settings
   - Suggest relevant sections
   - Context-aware visibility

4. **Responsive Fonts**
   - Scale text with panel width
   - Maintain readability
   - Use SF Pro adaptive sizing

## Conclusion

This redesign makes the inspector:
- **Robust** - Works at any width
- **Scalable** - Easy to add new sections
- **User-friendly** - Clear, scannable, accessible
- **Future-proof** - Adaptable design patterns

No more cutoff issues! 🎯
