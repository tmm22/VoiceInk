import SwiftUI
import AppKit

// MARK: - Context Switcher

struct ContextSwitcher: View {
    @Binding var selectedContext: ContextPanelDestination?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContextPanelDestination.allCases) { destination in
                    let isSelected = selectedContext == destination
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedContext = isSelected ? nil : destination
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: destination.icon)
                            Text(destination.title)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(destination.title)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Context Panel Card

struct ContextPanelCard: View {
    let selection: ContextPanelDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(selection.title, systemImage: selection.icon)
                .font(.headline)

            Divider()

            ContextPanelContent(selection: selection)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CardBackground(isSelected: false)
        )
    }
}

// MARK: - Context Rail View

struct ContextRailView: View {
    @Binding var selection: ContextPanelDestination?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(ContextPanelDestination.allCases) { destination in
                let isSelected = selection == destination
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = isSelected ? nil : destination
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: destination.icon)
                            .imageScale(.large)
                        Text(destination.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .help(destination.title)
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
    }
}

// MARK: - Context Panel Container

struct ContextPanelContainer: View {
    let constants: ResponsiveConstants
    let selection: ContextPanelDestination
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(selection.title, systemImage: selection.icon)
                        .font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.medium)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
            }
            .padding(.horizontal, constants.panelPadding)
            .padding(.top, constants.panelPadding)
            .padding(.bottom, constants.panelPadding * 0.6)

            // Scrollable content area
            ScrollView {
                ContextPanelContent(selection: selection)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, constants.panelPadding)
                    .padding(.bottom, constants.panelPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CardBackground(isSelected: false))
    }
}

// MARK: - Context Panel Content

struct ContextPanelContent: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let selection: ContextPanelDestination

    var body: some View {
        switch selection {
        case .queue:
            BatchQueueView()
                .environmentObject(viewModel)
        case .history:
            RecentGenerationsView()
                .environmentObject(viewModel)
        case .snippets:
            TextSnippetsView()
                .environmentObject(viewModel)
        case .glossary:
            PronunciationGlossaryView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Composer Utility Bar

struct ComposerUtilityBar: View {
    @Binding var activeUtility: ComposerUtility?

    var body: some View {
        Menu {
            ForEach(ComposerUtility.allCases) { utility in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeUtility = activeUtility == utility ? nil : utility
                    }
                } label: {
                    Label(utility.title, systemImage: utility.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .imageScale(.medium)
                    .foregroundColor(.accentColor)
                Text("Add Content")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.accentColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
        .help("Import text, transcribe audio, or add sample content")
    }
}