import SwiftUI

struct VoiceInkSidebar: View {
    let views: [ViewType]
    @Binding var selectedView: ViewType
    @Binding var hoveredView: ViewType?

    var body: some View {
        ZStack {
            VisualEffectView(material: VoiceInkTheme.Sidebar.backgroundMaterial, blendingMode: .withinWindow)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: VoiceInkSpacing.lg) {
                header

                Divider()
                    .padding(.horizontal, VoiceInkSpacing.md)

                VStack(spacing: VoiceInkSpacing.xs) {
                    ForEach(views, id: \.self) { viewType in
                        VoiceInkSidebarButton(
                            title: viewType.displayName,
                            systemImage: viewType.icon,
                            isSelected: selectedView == viewType,
                            isHovered: hoveredView == viewType
                        ) {
                            selectedView = viewType
                        }
                        .onHover { hovering in
                            hoveredView = hovering ? viewType : nil
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, VoiceInkSpacing.xl)
            .padding(.bottom, VoiceInkSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: VoiceInkSpacing.xs) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: VoiceInkRadius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.small, style: .continuous)
                            .stroke(VoiceInkTheme.Card.stroke, lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: VoiceInkSpacing.xxs) {
                Text(AppBrand.primaryName)
                    .font(.system(size: 13, weight: .semibold))
                Text(AppBrand.communityName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, VoiceInkSpacing.md)
    }
}

private struct VoiceInkSidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VoiceInkSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)

                Spacer()
            }
            .foregroundColor(.primary)
            .padding(.vertical, VoiceInkSpacing.xs)
            .padding(.horizontal, VoiceInkSpacing.md)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: VoiceInkRadius.small, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: VoiceInkRadius.small, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: VoiceInkRadius.small, style: .continuous)
                    .stroke(isSelected ? VoiceInkTheme.Card.selectedStroke : Color.clear, lineWidth: 1)
            )
    }

    private var fillColor: Color {
        if isSelected {
            return VoiceInkTheme.Palette.accent.opacity(VoiceInkTheme.Sidebar.selectedOpacity)
        } else if isHovered {
            return VoiceInkTheme.Palette.accent.opacity(VoiceInkTheme.Sidebar.hoverOpacity)
        } else {
            return Color.clear
        }
    }
}
