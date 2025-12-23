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
    @StateObject private var ttsViewModel = TTSViewModel()
    @State private var selectedView: ViewType = .metrics
    @State private var hasLoadedData = false
    @State private var showingShortcutCheatSheet = false
    @AppStorage("enableAIEnhancementFeatures") private var enableAIEnhancementFeatures = false
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
        }
        // inside ContentView body:
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            #if DEBUG
            print("ContentView: Received navigation notification")
            #endif
            if let destination = notification.userInfo?["destination"] as? String {
                #if DEBUG
                print("ContentView: Destination received: \(destination)")
                #endif
                switch destination {
                case "Settings":
                    #if DEBUG
                    print("ContentView: Navigating to Settings")
                    #endif
                    selectedView = .settings
                case "AI Models":
                    guard enableAIEnhancementFeatures else {
                        #if DEBUG
                        print("ContentView: AI features disabled; ignoring AI Models navigation")
                        #endif
                        return
                    }
                    #if DEBUG
                    print("ContentView: Navigating to AI Models")
                    #endif
                    selectedView = .models
                case "Community":
                    #if DEBUG
                    print("ContentView: Navigating to Community")
                    #endif
                    selectedView = .community
                case "History":
                    #if DEBUG
                    print("ContentView: Navigating to History")
                    #endif
                    selectedView = .history
                case "Permissions":
                    #if DEBUG
                    print("ContentView: Navigating to Permissions")
                    #endif
                    selectedView = .permissions
                case "Enhancement":
                    guard enableAIEnhancementFeatures else {
                        #if DEBUG
                        print("ContentView: AI features disabled; ignoring Enhancement navigation")
                        #endif
                        return
                    }
                    #if DEBUG
                    print("ContentView: Navigating to Enhancement")
                    #endif
                    selectedView = .enhancement
                case "Transcribe Audio":
                    // Ensure we switch to the Transcribe Audio view in-place
                    #if DEBUG
                    print("ContentView: Navigating to Transcribe Audio")
                    #endif
                    selectedView = .transcribeAudio
                case "Text to Speech":
                    guard enableAIEnhancementFeatures else {
                        #if DEBUG
                        print("ContentView: AI features disabled; ignoring Text to Speech navigation")
                        #endif
                        return
                    }
                    #if DEBUG
                    print("ContentView: Navigating to Text to Speech")
                    #endif
                    selectedView = .textToSpeech
                default:
                    #if DEBUG
                    print("ContentView: No matching destination found for: \(destination)")
                    #endif
                    break
                }
            } else {
                #if DEBUG
                print("ContentView: No destination in notification")
                #endif
            }
        }
        .onChange(of: enableAIEnhancementFeatures) { _, _ in
            ensureValidSelection()
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
                TextToSpeechView(viewModel: ttsViewModel)
            } else {
                FeatureUnavailablePlaceholder()
            }
        case .history:
            TranscriptionHistoryView(modelContext: modelContext)
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView(whisperPrompt: whisperState.whisperPrompt)
        case .powerMode:
            PowerModeView()
        case .settings:
            SettingsView(selectedTab: .general)
                .environmentObject(whisperState)
        case .community, .permissions:
             // These are now handled within Settings or removed from top-level
             SettingsView(selectedTab: settingsTab(for: selectedView))
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

 
