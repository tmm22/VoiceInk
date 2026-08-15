import SwiftUI
import AppKit

// MARK: - Compact Workspace

struct CompactWorkspace: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    @Binding var selectedContextPanel: ContextPanelDestination?
    @Binding var activeUtility: ComposerUtility?
    let focusInspector: () -> Void

    var body: some View {
        MainComposerColumn(
            isCompact: true,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            selectedContextPanel: $selectedContextPanel,
            activeUtility: $activeUtility,
            focusInspector: focusInspector
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .layoutPriority(1)
    }
}

// MARK: - Wide Workspace

struct WideWorkspace: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let constants: ResponsiveConstants
    @Binding var selectedContextPanel: ContextPanelDestination?
    @Binding var activeUtility: ComposerUtility?
    @Binding var isInspectorVisible: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let focusInspector: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ContextRailView(selection: $selectedContextPanel)
                .frame(width: constants.contextRailWidth)
                .background(Color(NSColor.windowBackgroundColor))

            if let selection = selectedContextPanel {
                Divider()
                ContextPanelContainer(
                    constants: constants,
                    selection: selection
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedContextPanel = nil
                    }
                }
                .frame(
                    minWidth: constants.contextPanelWidth.lowerBound,
                    idealWidth: constants.idealContextPanelWidth,
                    maxWidth: constants.contextPanelWidth.upperBound,
                    maxHeight: .infinity
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Divider()

            MainComposerColumn(
                isCompact: false,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                selectedContextPanel: $selectedContextPanel,
                activeUtility: $activeUtility,
                focusInspector: focusInspector
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)

            if isInspectorVisible {
                Divider()
                InspectorColumn(
                    isVisible: $isInspectorVisible
                )
                .frame(
                    minWidth: constants.inspectorWidth.lowerBound,
                    idealWidth: constants.idealInspectorWidth,
                    maxWidth: constants.inspectorWidth.upperBound
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Inspector Column

struct InspectorColumn: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isVisible: Bool

    var body: some View {
        TTSInspectorView(isVisible: $isVisible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}