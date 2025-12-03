import SwiftUI
import AppKit

// MARK: - TTS Workspace View

/// Main workspace view for the Text-to-Speech feature.
/// Component views are organized in extension files:
/// - TTSWorkspaceView+Enums.swift - ContextPanelDestination and ComposerUtility enums
/// - TTSWorkspaceView+CommandStrip.swift - CommandStripView and commandLabelFixedSize()
/// - TTSWorkspaceView+Workspace.swift - CompactWorkspace, WideWorkspace, InspectorColumn
/// - TTSWorkspaceView+Composer.swift - MainComposerColumn, ContextShelfView, ArticleSummaryCard, GenerationStatusFooter
/// - TTSWorkspaceView+ContextPanels.swift - ContextSwitcher, ContextPanelCard, ContextRailView, ContextPanelContainer, ContextPanelContent, ComposerUtilityBar
/// - TTSWorkspaceView+Utilities.swift - UtilityDetailView, SampleTextUtilityView, ChunkingHelperView, TranslationComparisonView, TranslationSettingsPopover, VoicePreviewPopover
/// - TTSWorkspaceView+PlaybackBar.swift - PlaybackBarView, SegmentMarkersView

struct TTSWorkspaceView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var showingAbout = false
    @State private var selectedContextPanel: ContextPanelDestination? = nil
    @State private var isInspectorVisible = false
    @State private var activeUtility: ComposerUtility?
    @State private var showingInspectorPopover = false
    @State private var lastPopoverDismissal: Date = .distantPast

    var body: some View {
        GeometryReader { proxy in
            let constants = ResponsiveConstants(width: proxy.size.width, height: proxy.size.height)
            let isCompact = proxy.size.width < 960
            let horizontalPadding = viewModel.isMinimalistMode ? constants.composerHorizontalPadding * 0.75 : constants.composerHorizontalPadding
            let commandVerticalPadding = viewModel.isMinimalistMode ? constants.commandStripVerticalPadding * 0.8 : constants.commandStripVerticalPadding
            let composerVerticalPadding = viewModel.isMinimalistMode ? constants.composerVerticalPadding * 0.8 : constants.composerVerticalPadding
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
        .preferredColorScheme(viewModel.colorSchemeOverride)
        .sheet(isPresented: $showingAbout) {
            TTSAboutSheetView()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay(
            HStack(spacing: 0) {
                Button(action: {
                    viewModel.playbackSpeed = max(0.5, viewModel.playbackSpeed - 0.25)
                    viewModel.applyPlaybackSpeed(save: true)
                }) { EmptyView() }
                .keyboardShortcut("[", modifiers: .command)

                Button(action: {
                    viewModel.playbackSpeed = min(2.0, viewModel.playbackSpeed + 0.25)
                    viewModel.applyPlaybackSpeed(save: true)
                }) { EmptyView() }
                .keyboardShortcut("]", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0.01)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        )
        .onAppear {
            viewModel.updateAvailableVoices()
        }
    }
}

// MARK: - TTS About Sheet View

struct TTSAboutSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("TTS Workspace")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Transform text into natural-sounding speech using AI voices from multiple providers.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("OpenAI TTS", systemImage: "checkmark.circle.fill")
                Label("ElevenLabs", systemImage: "checkmark.circle.fill")
                Label("Google Cloud TTS", systemImage: "checkmark.circle.fill")
                Label("Local TTS (Offline)", systemImage: "checkmark.circle.fill")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 400, height: 400)
    }
}
