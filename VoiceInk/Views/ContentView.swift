import SwiftUI
import SwiftData
import KeyboardShortcuts

// ViewType enum with all cases
enum ViewType: String, CaseIterable {
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
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct DynamicSidebar: View {
    let views: [ViewType]
    @Binding var selectedView: ViewType
    @Binding var hoveredView: ViewType?
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var buttonAnimation

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
                }
                
                Text("VoiceLink")
                    .font(.system(size: 12, weight: .medium))
                Text("Community")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(2)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            
            ForEach(views, id: \.self) { viewType in
                DynamicSidebarButton(
                    title: viewType.rawValue,
                    systemImage: viewType.icon,
                    isSelected: selectedView == viewType,
                    isHovered: hoveredView == viewType,
                    namespace: buttonAnimation
                ) {
                    selectedView = viewType
                }
                .onHover { isHovered in
                    hoveredView = isHovered ? viewType : nil
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DynamicSidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isHovered: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16, height: 16)
                
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    }
                }
            )
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                }
            )
            .padding(.horizontal, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @StateObject private var ttsViewModel = TTSViewModel()
    @State private var selectedView: ViewType = .metrics
    @State private var hoveredView: ViewType?
    @State private var hasLoadedData = false
    @AppStorage("enableAIEnhancementFeatures") private var enableAIEnhancementFeatures = false

    private var availableViews: [ViewType] {
        ViewType.allCases.filter { viewType in
            if !enableAIEnhancementFeatures && (viewType == .models || viewType == .enhancement || viewType == .textToSpeech) {
                return false
            }
            return true
        }
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
            DynamicSidebar(
                views: availableViews,
                selectedView: $selectedView,
                hoveredView: $hoveredView
            )
            .frame(width: 200)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(.hidden, for: .automatic)
                .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 730)
        .onAppear {
            hasLoadedData = true
            ensureValidSelection()
        }
        // inside ContentView body:
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            print("ContentView: Received navigation notification")
            if let destination = notification.userInfo?["destination"] as? String {
                print("ContentView: Destination received: \(destination)")
                switch destination {
                case "Settings":
                    print("ContentView: Navigating to Settings")
                    selectedView = .settings
                case "AI Models":
                    guard enableAIEnhancementFeatures else {
                        print("ContentView: AI features disabled; ignoring AI Models navigation")
                        return
                    }
                    print("ContentView: Navigating to AI Models")
                    selectedView = .models
                case "Community":
                    print("ContentView: Navigating to Community")
                    selectedView = .community
                case "History":
                    print("ContentView: Navigating to History")
                    selectedView = .history
                case "Permissions":
                    print("ContentView: Navigating to Permissions")
                    selectedView = .permissions
                case "Enhancement":
                    guard enableAIEnhancementFeatures else {
                        print("ContentView: AI features disabled; ignoring Enhancement navigation")
                        return
                    }
                    print("ContentView: Navigating to Enhancement")
                    selectedView = .enhancement
                case "Transcribe Audio":
                    // Ensure we switch to the Transcribe Audio view in-place
                    print("ContentView: Navigating to Transcribe Audio")
                    selectedView = .transcribeAudio
                case "Text to Speech":
                    guard enableAIEnhancementFeatures else {
                        print("ContentView: AI features disabled; ignoring Text to Speech navigation")
                        return
                    }
                    print("ContentView: Navigating to Text to Speech")
                    selectedView = .textToSpeech
                default:
                    print("ContentView: No matching destination found for: \(destination)")
                    break
                }
            } else {
                print("ContentView: No destination in notification")
            }
        }
        .onChange(of: enableAIEnhancementFeatures) { _, _ in
            ensureValidSelection()
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedView {
        case .metrics:
            if isSetupComplete {
                MetricsView(skipSetupCheck: true)
            } else {
                MetricsSetupView()
                    .environmentObject(hotkeyManager)
            }
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
        case .community:
            LicenseManagementView()
        case .permissions:
            PermissionsView()
        }
    }

    private func ensureValidSelection() {
        guard let firstAvailable = availableViews.first else { return }
        if !availableViews.contains(selectedView) {
            selectedView = firstAvailable
        }
    }
}

private struct FeatureUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("AI enhancements are disabled.")
                .font(.headline)
            Text("Enable AI enhancement features in Settings to access this workspace.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

 
