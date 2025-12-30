import SwiftUI
import AppKit

struct SidebarSection: Identifiable {
    let id = UUID()
    let title: String?
    let items: [ViewType]
}

struct VoiceInkSidebar: View {
    let sections: [SidebarSection]
    @Binding var selectedView: ViewType
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, VoiceInkSpacing.md)
                .padding(.bottom, VoiceInkSpacing.sm)
            
            List(selection: $selectedView) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            let isSelected = selectedView == item
                            NavigationLink(value: item) {
                                Label(item.displayName, systemImage: item.icon)
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                            }
                            .listRowBackground(rowBackground(isSelected: isSelected))
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
            .background(SidebarSelectionHighlightSuppressor())
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

    private func rowBackground(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: VoiceInkRadius.small, style: .continuous)
                    .fill(selectionColor)
                    .padding(.horizontal, 6)
            } else {
                Color.clear
            }
        }
    }

    private var selectionColor: Color {
        let nsColor: NSColor = controlActiveState == .inactive ? .secondarySelectedControlColor : .alternateSelectedControlColor
        return Color(nsColor: nsColor)
    }
}

private struct SidebarSelectionHighlightSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ConfiguratorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ConfiguratorView)?.configureIfNeeded()
    }
}

private final class ConfiguratorView: NSView {
    private weak var configuredTableView: NSTableView?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureIfNeeded()
    }

    func configureIfNeeded() {
        guard let tableView = findTableView() else { return }
        guard configuredTableView !== tableView else { return }
        tableView.selectionHighlightStyle = .none
        tableView.reloadData()
        configuredTableView = tableView
    }

    private func findTableView() -> NSTableView? {
        var view: NSView? = superview
        while let current = view {
            if let tableView = firstTableView(in: current) {
                return tableView
            }
            view = current.superview
        }
        return nil
    }

    private func firstTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }
        for subview in view.subviews {
            if let match = firstTableView(in: subview) {
                return match
            }
        }
        return nil
    }
}
