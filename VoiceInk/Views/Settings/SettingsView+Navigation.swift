import SwiftUI

// MARK: - Settings Navigation Rail

struct SettingsNavigationRail: View {
    let tabs: [SettingsTab]
    @Binding var selectedTab: SettingsTab
    @Binding var searchText: String
    let tabHasMatches: (SettingsTab) -> Bool
    let onSelect: (SettingsTab) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.xs) {
            // Search Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Search settings...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, VoiceInkSpacing.md)
            .padding(.vertical, VoiceInkSpacing.sm)
            .voiceInkCardBackground()
            .padding(.bottom, VoiceInkSpacing.sm)
            
            ForEach(tabs) { tab in
                let hasMatches = tabHasMatches(tab)
                if searchText.isEmpty || hasMatches {
                    SettingsRailItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        dimmed: !searchText.isEmpty && !hasMatches
                    ) {
                        onSelect(tab)
                    }
                }
            }
            
            if !searchText.isEmpty && !tabs.contains(where: { tabHasMatches($0) }) {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, VoiceInkSpacing.xl)
            }
            
            Spacer()
        }
        .padding(VoiceInkSpacing.md)
    }
}

// MARK: - Settings Rail Item

struct SettingsRailItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    var dimmed: Bool = false
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: VoiceInkSpacing.sm) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
            }
            .padding(.horizontal, VoiceInkSpacing.md)
            .padding(.vertical, VoiceInkSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                    .fill(isSelected ? VoiceInkTheme.Palette.elevatedSurface : (isHovering ? VoiceInkTheme.Palette.surface.opacity(0.5) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .primary : .secondary)
        .opacity(dimmed ? 0.4 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}