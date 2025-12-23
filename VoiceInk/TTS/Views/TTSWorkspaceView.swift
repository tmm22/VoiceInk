import SwiftUI

// MARK: - TTS Workspace View

/// Main workspace view for the Text-to-Speech feature.
/// Component views are organized in extension files:
/// - TTSWorkspaceLayoutView.swift - Geometry layout and inspector handling
/// - TTSAboutSheetView.swift - About sheet content
/// - TTSWorkspaceView+Enums.swift - ContextPanelDestination and ComposerUtility enums
/// - TTSWorkspaceView+CommandStrip.swift - CommandStripView and commandLabelFixedSize()
/// - TTSWorkspaceView+Workspace.swift - CompactWorkspace, WideWorkspace, InspectorColumn
/// - TTSWorkspaceView+Composer.swift - MainComposerColumn, ContextShelfView, ArticleSummaryCard, GenerationStatusFooter
/// - TTSWorkspaceView+ContextPanels.swift - ContextSwitcher, ContextPanelCard, ContextRailView, ContextPanelContainer, ContextPanelContent, ComposerUtilityBar
/// - TTSWorkspaceView+Utilities.swift - UtilityDetailView, SampleTextUtilityView, ChunkingHelperView, TranslationComparisonView, TranslationSettingsPopover, VoicePreviewPopover
/// - TTSWorkspaceView+PlaybackBar.swift - PlaybackBarView, SegmentMarkersView

struct TTSWorkspaceView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var playback: TTSPlaybackViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @State private var showingAbout = false
    @State private var selectedContextPanel: ContextPanelDestination? = nil
    @State private var isInspectorVisible = false
    @State private var activeUtility: ComposerUtility?
    @State private var showingInspectorPopover = false
    @State private var lastPopoverDismissal: Date = .distantPast

    var body: some View {
        TTSWorkspaceLayoutView(
            showingAbout: $showingAbout,
            selectedContextPanel: $selectedContextPanel,
            isInspectorVisible: $isInspectorVisible,
            activeUtility: $activeUtility,
            showingInspectorPopover: $showingInspectorPopover,
            lastPopoverDismissal: $lastPopoverDismissal
        )
        .preferredColorScheme(settings.colorSchemeOverride)
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
                    playback.playbackSpeed = max(0.5, playback.playbackSpeed - 0.25)
                    playback.applyPlaybackSpeed(save: true)
                }) { EmptyView() }
                .keyboardShortcut("[", modifiers: .command)

                Button(action: {
                    playback.playbackSpeed = min(2.0, playback.playbackSpeed + 0.25)
                    playback.applyPlaybackSpeed(save: true)
                }) { EmptyView() }
                .keyboardShortcut("]", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0.01)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        )
        .onAppear {
            settings.updateAvailableVoices()
        }
    }
}
