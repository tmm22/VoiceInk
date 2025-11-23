import SwiftUI

struct SidebarSection: Identifiable {
    let id = UUID()
    let title: String?
    let items: [ViewType]
}

struct VoiceInkSidebar: View {
    let sections: [SidebarSection]
    @Binding var selectedView: ViewType

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, VoiceInkSpacing.md)
                .padding(.bottom, VoiceInkSpacing.sm)
            
            List(selection: $selectedView) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            NavigationLink(value: item) {
                                Label(item.displayName, systemImage: item.icon)
                            }
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
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
