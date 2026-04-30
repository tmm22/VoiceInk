import SwiftUI
import SwiftData
import Sparkle
import AppKit
import OSLog
import AppIntents
import FluidAudio
import Security

@main
struct VoiceInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    let containerInitializationFailed: Bool
    
    @StateObject private var whisperState: WhisperState
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @State private var showMenuBarIcon = true

    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared

    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared

    // Model prewarm service for optimizing model on wake from sleep
    @StateObject private var prewarmService: ModelPrewarmService
    
    // MetricKit manager for DEBUG performance monitoring
    #if DEBUG
    @available(macOS 12.0, *)
    private var metricsManager: MetricsManager { MetricsManager.shared }
    #endif
    
    init() {
        // Disable shared HTTP response caching so API responses are not persisted to Cache.db.
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)

        AppDefaults.registerDefaults()

        // Migrate API keys from UserDefaults to Keychain (runs once on first launch after update)
        APIKeyMigrationService.migrateAPIKeysIfNeeded()
        
        if !AppSettings.contains(key: AppSettings.Keys.powerModeUIFlag) {
            let hasEnabledPowerModes = PowerModeManager.shared.configurations.contains { $0.isEnabled }
            AppSettings.General.powerModeUIFlag = hasEnabledPowerModes
        }

        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Initialization")
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self
        ])
        var initializationFailed = false
        
        // Attempt 1: Try persistent storage
        if let persistentContainer = Self.createPersistentContainer(schema: schema, logger: logger) {
            container = persistentContainer
        }
        // Attempt 2: Try in-memory storage
        else if let memoryContainer = Self.createInMemoryContainer(schema: schema, logger: logger) {
            container = memoryContainer

            logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")

            // Show alert to user about storage issue
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "Storage Warning"
                alert.informativeText = "VoiceInk couldn't access its storage location. Your transcriptions will not be saved between sessions."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        // All attempts failed
        else {
            logger.critical("ModelContainer initialization failed")
            initializationFailed = true

            // Create minimal in-memory container to satisfy initialization
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: schema, configurations: [config])) ?? {
                preconditionFailure("Unable to create ModelContainer. SwiftData is unavailable.")
            }()
        }
        
        containerInitializationFailed = initializationFailed
        
        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)
        
        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)
        
        if AppSettings.General.enableAIEnhancementFeatures == nil {
            AppSettings.General.enableAIEnhancementFeatures = true
            logger.info("Defaulted AI enhancement feature visibility to enabled for first launch")
        }

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)
        if AppSettings.General.enableAIEnhancementFeatures == false {
            enhancementService.isEnhancementEnabled = false
        }
        
        let whisperState = WhisperState(modelContext: container.mainContext, enhancementService: enhancementService)
        _whisperState = StateObject(wrappedValue: whisperState)
        
        let hotkeyManager = HotkeyManager(whisperState: whisperState)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)

        let menuBarManager = MenuBarManager()
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        menuBarManager.configure(modelContainer: container, whisperState: whisperState)

        let activeWindowService = ActiveWindowService.shared
        activeWindowService.configure(with: enhancementService)
        activeWindowService.configureWhisperState(whisperState)
        _activeWindowService = StateObject(wrappedValue: activeWindowService)

        
        let prewarmService = ModelPrewarmService(whisperState: whisperState, modelContext: container.mainContext)
        _prewarmService = StateObject(wrappedValue: prewarmService)

        appDelegate.menuBarManager = menuBarManager

        // Ensure no lingering recording state from previous runs
        Task {
            await whisperState.resetOnLaunch()
        }

        AppShortcuts.updateAppShortcutParameters()
    }
    
    // MARK: - Container Creation Helpers
    
    private static let dictionaryCloudKitContainerIdentifier = "iCloud.com.prakashjoshipax.VoiceInk"
    
    private static func shouldUseDictionaryCloudKit(logger: Logger) -> Bool {
        if ProcessInfo.processInfo.environment["VOICEINK_DISABLE_DICTIONARY_CLOUDKIT"] == "1" {
            logger.notice("Dictionary CloudKit sync disabled by VOICEINK_DISABLE_DICTIONARY_CLOUDKIT")
            return false
        }
        
        guard hasICloudContainerEntitlement(dictionaryCloudKitContainerIdentifier) else {
            logger.notice("Dictionary CloudKit sync disabled: missing iCloud container entitlement")
            return false
        }
        
        guard FileManager.default.ubiquityIdentityToken != nil else {
            logger.notice("Dictionary CloudKit sync disabled: iCloud account unavailable")
            return false
        }
        
        return true
    }
    
    private static func hasICloudContainerEntitlement(_ containerIdentifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let raw = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) else {
            return false
        }
        
        if let identifiers = raw as? [String] {
            return identifiers.contains(containerIdentifier)
        }
        
        if let identifiers = raw as? [Any] {
            return identifiers.compactMap { $0 as? String }.contains(containerIdentifier)
        }
        
        return false
    }
    
    private static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Use bundle identifier for app-specific storage directory
            let bundleID = Bundle.main.bundleIdentifier ?? "com.tmm22.VoiceLinkCommunity"
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(bundleID, isDirectory: true)
            
            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            // Define storage locations
            let defaultStoreURL = appSupportURL.appendingPathComponent("default.store")
            let dictionaryStoreURL = appSupportURL.appendingPathComponent("dictionary.store")

            // Transcript configuration
            let transcriptSchema = Schema([Transcription.self])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                url: defaultStoreURL,
                cloudKitDatabase: .none
            )

            // Dictionary configuration (CloudKit is enabled only when runtime supports it)
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
            let dictionaryCloudKitDatabase: ModelConfiguration.CloudKitDatabase =
                shouldUseDictionaryCloudKit(logger: logger)
                ? .private(dictionaryCloudKitContainerIdentifier)
                : .none
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                url: dictionaryStoreURL,
                cloudKitDatabase: dictionaryCloudKitDatabase
            )

            // Initialize container
            return try ModelContainer(
                for: schema,
                configurations: transcriptConfig, dictionaryConfig
            )
        } catch {
            logger.error("Failed to create persistent ModelContainer: \(AppLogger.errorMetadata(error), privacy: .public)")
            return nil
        }
    }
    
    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Transcript configuration
            let transcriptSchema = Schema([Transcription.self])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                isStoredInMemoryOnly: true
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                isStoredInMemoryOnly: true
            )

            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig)
        } catch {
            logger.error("Failed to create in-memory ModelContainer: \(AppLogger.errorMetadata(error), privacy: .public)")
            return nil
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(whisperState)
                    .environmentObject(hotkeyManager)
                    .environmentObject(updaterViewModel)
                    .environmentObject(menuBarManager)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .modelContainer(container)
                    .onAppear {
                        // Check if container initialization failed
                        if containerInitializationFailed {
                            let alert = NSAlert()
                            alert.messageText = "Critical Storage Error"
                            alert.informativeText = "VoiceInk cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: "Quit")
                            alert.runModal()

                            NSApplication.shared.terminate(nil)
                            return
                        }

                        // Migrate dictionary data from UserDefaults to SwiftData (one-time operation)
                        DictionaryMigrationService.shared.migrateIfNeeded(context: container.mainContext)

                        updaterViewModel.silentlyCheckForUpdates()
                        if enableAnnouncements {
                            AnnouncementsService.shared.start()
                        }
                        
                        // Start the transcription auto-cleanup service (handles immediate and scheduled transcript deletion)
                        transcriptionAutoCleanupService.startMonitoring(modelContext: container.mainContext)
                        
                        // Clean up expired trash items (items deleted more than 30 days ago)
                        Task {
                            await TrashCleanupService.shared.cleanupExpiredTrashItems(modelContext: container.mainContext)
                        }
                        
                        // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                        if !AppSettings.Cleanup.isTranscriptionCleanupEnabled {
                            audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                        }
                        
                        // Process any pending open-file request now that the main ContentView is ready.
                        if let pendingURL = appDelegate.pendingOpenFileURL {
                            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": pendingURL])
                            }
                            appDelegate.pendingOpenFileURL = nil
                        }
                        
                        // Register MetricKit for DEBUG performance monitoring
                        #if DEBUG
                        if #available(macOS 12.0, *) {
                            metricsManager.register()
                        }
                        #endif
                    }
                    .background(WindowAccessor { window in
                        WindowManager.shared.configureWindow(window)
                    })
                    .onDisappear {
                        AnnouncementsService.shared.stop()
                        whisperState.unloadModel()
                        
                        // Stop the transcription auto-cleanup service
                        transcriptionAutoCleanupService.stopMonitoring()
                        
                        // Stop the automatic audio cleanup process
                        audioCleanupManager.stopAutomaticCleanup()
                        
                        // Unregister MetricKit
                        #if DEBUG
                        if #available(macOS 12.0, *) {
                            metricsManager.unregister()
                        }
                        #endif
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(hotkeyManager)
                    .environmentObject(whisperState)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .frame(minWidth: 880, minHeight: 780)
                    .background(WindowAccessor { window in
                        if window.identifier == nil || window.identifier != NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.onboardingWindow") {
                            WindowManager.shared.configureOnboardingPanel(window)
                        }
                    })
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
            
            CommandGroup(after: .help) {
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .showShortcutCheatSheet, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
        
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(whisperState)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .environmentObject(updaterViewModel)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
        } label: {
            let image: NSImage = {
                if let img = NSImage(named: "menuBarIcon") {
                    let ratio = img.size.height / img.size.width
                    img.size.height = 22
                    img.size.width = 22 / ratio
                    return img
                } else {
                    // Fallback system image if custom asset is missing
                    let fallback = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceInk") ?? NSImage()
                    fallback.size = NSSize(width: 18, height: 22)
                    return fallback
                }
            }()

            Image(nsImage: image)
                .accessibilityLabel(AppBrand.communityName)
        }
        .menuBarExtraStyle(.menu)
        
        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Menu Bar Only") {
                menuBarManager.isMenuBarOnly.toggle()
            }
        }
        #endif
    }
}

@MainActor
class UpdaterViewModel: ObservableObject {
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    
    private let updaterController: SPUStandardUpdaterController?
    
    @Published var canCheckForUpdates = false
    
    init() {
        guard AppBrand.supportsInAppUpdates else {
            updaterController = nil
            canCheckForUpdates = true
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController = controller
        
        // Enable automatic update checking
        controller.updater.automaticallyChecksForUpdates = autoUpdateCheck
        controller.updater.updateCheckInterval = 24 * 60 * 60
        
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    func toggleAutoUpdates(_ value: Bool) {
        guard let updaterController else { return }
        updaterController.updater.automaticallyChecksForUpdates = value
    }
    
    func checkForUpdates() {
        guard let updaterController else {
            if let url = AppBrand.releasesURL {
                NSWorkspace.shared.open(url)
            }
            return
        }

        // This is for manual checks - will show UI
        updaterController.checkForUpdates(nil)
    }
    
    func silentlyCheckForUpdates() {
        guard let updaterController else { return }

        // This checks for updates in the background without showing UI unless an update is found
        updaterController.updater.checkForUpdatesInBackground()
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
