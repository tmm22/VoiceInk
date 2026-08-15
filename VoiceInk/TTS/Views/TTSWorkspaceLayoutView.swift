import SwiftUI
import AppKit

struct TTSWorkspaceLayoutView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @Binding var showingAbout: Bool
    @Binding var selectedContextPanel: ContextPanelDestination?
    @Binding var isInspectorVisible: Bool
    @Binding var activeUtility: ComposerUtility?
    @Binding var showingInspectorPopover: Bool
    @Binding var lastPopoverDismissal: Date

    var body: some View {
        GeometryReader { proxy in
            let constants = ResponsiveConstants(width: proxy.size.width, height: proxy.size.height)
            let isCompact = proxy.size.width < 960
            let horizontalPadding = settings.isMinimalistMode ? constants.composerHorizontalPadding * 0.75 : constants.composerHorizontalPadding
            let commandVerticalPadding = settings.isMinimalistMode ? constants.commandStripVerticalPadding * 0.8 : constants.commandStripVerticalPadding
            let composerVerticalPadding = settings.isMinimalistMode ? constants.composerVerticalPadding * 0.8 : constants.composerVerticalPadding
            // Disable minimum window check for now - causing issues
            let isBelowMinimum = false // ResponsiveConstants.isBelowMinimum(width: proxy.size.width, height: proxy.size.height)

            // Custom binding to track dismissal time precisely when system updates the state
            let popoverBinding = Binding<Bool>(
                get: { showingInspectorPopover },
                set: { newValue in
                    if showingInspectorPopover && !newValue {
                        lastPopoverDismissal = Date()
                    }
                    showingInspectorPopover = newValue
                }
            )

            ZStack {
                VStack(spacing: 0) {
                    CommandStripView(
                        constants: constants,
                        isCompact: isCompact,
                        isInspectorVisible: isCompact ? showingInspectorPopover : isInspectorVisible,
                        showingAbout: $showingAbout,
                        showingInspectorPopover: popoverBinding,
                        toggleInspector: {
                            if isCompact {
                                // In compact mode, we toggle the popover
                                // If it's open, close it.
                                if showingInspectorPopover {
                                    showingInspectorPopover = false
                                } else {
                                    // Prevent immediate re-opening if just dismissed by system
                                    let timeSinceDismissal = Date().timeIntervalSince(lastPopoverDismissal)
                                    if timeSinceDismissal > 0.5 {
                                        showingInspectorPopover = true
                                    }
                                }
                            } else {
                                // In wide mode, we toggle the sidebar visibility
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isInspectorVisible.toggle()
                                }
                            }
                        },
                        focusInspector: {
                            if isCompact {
                                showingInspectorPopover = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isInspectorVisible = true
                                }
                            }
                        }
                    )
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, commandVerticalPadding)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    if isCompact {
                        CompactWorkspace(
                            horizontalPadding: horizontalPadding,
                            verticalPadding: composerVerticalPadding,
                            selectedContextPanel: $selectedContextPanel,
                            activeUtility: $activeUtility,
                            focusInspector: {
                                showingInspectorPopover = true
                            }
                        )
                        .environmentObject(viewModel)
                    } else {
                        WideWorkspace(
                            constants: constants,
                            selectedContextPanel: $selectedContextPanel,
                            activeUtility: $activeUtility,
                            isInspectorVisible: $isInspectorVisible,
                            horizontalPadding: horizontalPadding,
                            verticalPadding: composerVerticalPadding,
                            focusInspector: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isInspectorVisible = true
                                }
                            }
                        )
                        .environmentObject(viewModel)
                    }

                    Divider()

                    PlaybackBarView(horizontalPadding: horizontalPadding)
                        .background(Color(NSColor.windowBackgroundColor))
                }
                .background(Color(NSColor.controlBackgroundColor).ignoresSafeArea())

                // Minimum window size warning overlay
                if isBelowMinimum {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Window Too Small")
                            .font(.headline)

                        Text("Please resize to at least \(Int(ResponsiveConstants.minimumWindowWidth))×\(Int(ResponsiveConstants.minimumWindowHeight)) for the best experience")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }
}
