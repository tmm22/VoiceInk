import SwiftUI
import SwiftData
import KeyboardShortcuts

// ViewType enum with all cases
enum ViewType: String, CaseIterable, Identifiable {
    case metrics = "Dashboard"
    case transcribeAudio = "Transcribe Audio"
    case textToSpeech = "Text to Speech"
    case history = "History"
    case models = "AI Models"
    case enhancement = "Enhancement"
    case powerMode = "Power Mode"
    case permissions = "Permissions"
    case audioInput = "Audio Input"
    case dictionary = "Dictionary"
    case settings = "Settings"
    case community = "Community"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .metrics: return "gauge.medium"
        case .transcribeAudio: return "waveform.circle.fill"
        case .textToSpeech: return "speaker.wave.3.fill"
        case .history: return "doc.text.fill"
        case .models: return "brain.head.profile"
        case .enhancement: return "wand.and.stars"
        case .powerMode: return "sparkles.square.fill.on.square"
        case .permissions: return "shield.fill"
        case .audioInput: return "mic.fill"
        case .dictionary: return "character.book.closed.fill"
        case .settings: return "gearshape.fill"
        case .community: return "hands.sparkles.fill"
        }
    }

    var displayName: String { rawValue }

    var requiresAIEnhancement: Bool {
        switch self {
        case .models, .enhancement, .textToSpeech:
            return true
        default:
            return false
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @State private var ttsViewModel: TTSViewModel?
    @State private var selectedView: ViewType = .metrics
    @State private var hasLoadedData = false
    @State private var showingShortcutCheatSheet = false
    @AppStorage("enableAIEnhancementFeatures") private var enableAIEnhancementFeatures = true
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    private var sidebarSections: [SidebarSection] {
        var sections: [SidebarSection] = []
        
        // Primary Section
        sections.append(SidebarSection(title: nil, items: [.metrics, .transcribeAudio, .history]))
        
        // AI Workspace
        if enableAIEnhancementFeatures {
            sections.append(SidebarSection(title: "AI Workspace", items: [.textToSpeech, .models, .powerMode, .enhancement]))
        }
        
        // System
        sections.append(SidebarSection(title: nil, items: [.settings]))
        
        return sections
    }
    
    private var isSetupComplete: Bool {
        hasLoadedData &&
        whisperState.currentTranscriptionModel != nil &&
        hotkeyManager.selectedHotkey1 != .none &&
        AXIsProcessTrusted() &&
        CGPreflightScreenCaptureAccess()
    }

    var body: some View {
        NavigationSplitView {
            VoiceInkSidebar(
                sections: sidebarSections,
                selectedView: $selectedView
            )
            .frame(width: 220)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            AppBackgroundView(material: .hudWindow) {
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar(.hidden, for: .automatic)
                    .navigationTitle("")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1200, idealWidth: 1440, minHeight: 800, idealHeight: 900)
        .onAppear {
            hasLoadedData = true
            ensureValidSelection()
            loadTTSViewModelIfNeeded(for: selectedView)
        }
        // inside ContentView body:
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            AppLogger.ui.debug("ContentView received navigation notification")
            if let destination = notification.userInfo?["destination"] as? String {
                AppLogger.ui.debug("ContentView received a navigation destination")
                switch destination {
                case "Settings":
                    AppLogger.ui.debug("ContentView navigating to Settings")
                    selectedView = .settings
                case "AI Models":
                    guard enableAIEnhancementFeatures else {
                        AppLogger.ui.info("ContentView blocked AI Models navigation because AI features are disabled")
                        return
                    }
                    AppLogger.ui.debug("ContentView navigating to AI Models")
                    selectedView = .models
                case "Community":
                    AppLogger.ui.debug("ContentView navigating to Community")
                    selectedView = .community
                case "History":
                    AppLogger.ui.debug("ContentView navigating to History")
                    selectedView = .history
                case "Permissions":
                    AppLogger.ui.debug("ContentView navigating to Permissions")
                    selectedView = .permissions
                case "Enhancement":
                    guard enableAIEnhancementFeatures else {
                        AppLogger.ui.info("ContentView blocked Enhancement navigation because AI features are disabled")
                        return
                    }
                    AppLogger.ui.debug("ContentView navigating to Enhancement")
                    selectedView = .enhancement
                case "Transcribe Audio":
                    // Ensure we switch to the Transcribe Audio view in-place
                    AppLogger.ui.debug("ContentView navigating to Transcribe Audio")
                    selectedView = .transcribeAudio
                case "Text to Speech":
                    guard enableAIEnhancementFeatures else {
                        AppLogger.ui.info("ContentView blocked Text to Speech navigation because AI features are disabled")
                        return
                    }
                    AppLogger.ui.debug("ContentView navigating to Text to Speech")
                    selectedView = .textToSpeech
                default:
                    AppLogger.ui.debug("ContentView found no matching navigation destination")
                    break
                }
            } else {
                AppLogger.ui.error("ContentView received a navigation notification without a destination")
            }
        }
        .onChange(of: enableAIEnhancementFeatures) { _, _ in
            ensureValidSelection()
            loadTTSViewModelIfNeeded(for: selectedView)
        }
        .onChange(of: selectedView) { _, newValue in
            loadTTSViewModelIfNeeded(for: newValue)
        }
        .sheet(isPresented: $showingShortcutCheatSheet) {
            KeyboardShortcutCheatSheet()
                .environmentObject(hotkeyManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showShortcutCheatSheet)) { _ in
            showingShortcutCheatSheet = true
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedView {
        case .metrics:
            MetricsView()
        case .models:
            if enableAIEnhancementFeatures {
                ModelManagementView(whisperState: whisperState)
            } else {
                FeatureUnavailablePlaceholder()
            }
        case .enhancement:
            if enableAIEnhancementFeatures {
                EnhancementSettingsView()
            } else {
                FeatureUnavailablePlaceholder()
            }
        case .transcribeAudio:
            AudioTranscribeView()
        case .textToSpeech:
            if enableAIEnhancementFeatures {
                if let ttsViewModel {
                    TextToSpeechView(viewModel: ttsViewModel)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            loadTTSViewModelIfNeeded(for: .textToSpeech)
                        }
                }
            } else {
                FeatureUnavailablePlaceholder()
            }
        case .history:
            TranscriptionHistoryView()
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView(whisperPrompt: whisperState.whisperPrompt)
        case .powerMode:
            PowerModeView()
        case .settings:
            SettingsView()
                .environmentObject(whisperState)
        case .community, .permissions:
             // These are now handled within Settings or removed from top-level
             SettingsView()
                 .environmentObject(whisperState)
        }
    }
    
    private func settingsTab(for viewType: ViewType) -> SettingsTab {
        switch viewType {
        case .audioInput: return .audio
        case .dictionary: return .transcription
        case .permissions: return .permissions
        case .community: return .general
        default: return .general
        }
    }

    private func ensureValidSelection() {
        // Gather all available views from sections
        let allAvailableViews = sidebarSections.flatMap { $0.items }
        
        // If current selection is not in available views (and not one of the views moved to settings), reset to default
        if !allAvailableViews.contains(selectedView) {
            // Allow staying on views that were moved to settings if we are already there? 
            // No, if we are simplifying, we should redirect to settings if they select something that's now IN settings.
            // But for now, let's just default to .metrics if invalid
             
            // Check if it's one of the moved views, if so, redirect to Settings
            if [.audioInput, .dictionary, .permissions, .community].contains(selectedView) {
                selectedView = .settings
            } else {
                selectedView = .metrics
            }
        }
    }

    private func loadTTSViewModelIfNeeded(for view: ViewType) {
        guard enableAIEnhancementFeatures else { return }
        guard view == .textToSpeech else { return }
        guard ttsViewModel == nil else { return }
        ttsViewModel = TTSViewModel()
    }
}

private struct FeatureUnavailablePlaceholder: View {
    var body: some View {
        VStack {
            VoiceInkCard {
                VStack(spacing: VoiceInkSpacing.md) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("AI enhancements are disabled.")
                        .voiceInkHeadline()

                    Text("Enable AI enhancement features in Settings to access this workspace.")
                        .voiceInkSubheadline()
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(VoiceInkSpacing.xl)
    }
}

 
