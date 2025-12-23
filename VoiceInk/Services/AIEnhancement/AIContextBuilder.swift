import Foundation
import SwiftData
import AppKit

@MainActor
class AIContextBuilder {
    // Services
    private let screenCaptureService: ScreenCaptureService
    private let customVocabularyService: CustomVocabularyService
    private let activeWindowService: ActiveWindowService
    private let focusedElementService: FocusedElementService
    private let selectedFileService: SelectedFileService
    private let calendarService: CalendarService
    private let browserContentService: BrowserContentService
    private let conversationHistoryService: ConversationHistoryService?
    private let tokenBudgetManager: TokenBudgetManager
    private let cacheManager = ContextCacheManager.shared
    
    // State
    private var capturedClipboard: ContextSection?
    private var capturedScreen: ScreenCaptureContext?
    private var capturedApplication: ApplicationContext?
    private var capturedFocusedElement: FocusedElementContext?
    private var capturedFiles: [FileContext]?
    private var capturedCalendar: CalendarContext?
    private var capturedBrowserContent: BrowserContentContext?
    
    init(
        screenCaptureService: ScreenCaptureService? = nil,
        customVocabularyService: CustomVocabularyService = CustomVocabularyService.shared,
        activeWindowService: ActiveWindowService? = nil,
        focusedElementService: FocusedElementService = FocusedElementService.shared,
        selectedFileService: SelectedFileService = SelectedFileService.shared,
        calendarService: CalendarService = CalendarService.shared,
        browserContentService: BrowserContentService = BrowserContentService.shared,
        modelContext: ModelContext? = nil
    ) {
        self.screenCaptureService = screenCaptureService ?? ScreenCaptureService()
        self.customVocabularyService = customVocabularyService
        self.activeWindowService = activeWindowService ?? ActiveWindowService.shared
        self.focusedElementService = focusedElementService
        self.selectedFileService = selectedFileService
        self.calendarService = calendarService
        self.browserContentService = browserContentService
        if let context = modelContext {
            self.conversationHistoryService = ConversationHistoryService(modelContext: context)
        } else {
            self.conversationHistoryService = nil
        }
        self.tokenBudgetManager = TokenBudgetManager()
    }
    
    /// Capture context that must be grabbed immediately (e.g. at recording start)
    func captureImmediateContext() async {
        // Run independent capture tasks in parallel
        // We use a task group to ensure we wait for all of them, but they run concurrently
        // Note: Services are responsible for backgrounding their heavy work
        
        await withTaskGroup(of: Void.self) { group in
            // 1. Clipboard
            group.addTask { @MainActor in
                if let clipboardString = NSPasteboard.general.string(forType: .string), !clipboardString.isEmpty {
                    self.capturedClipboard = ContextSection(
                        content: clipboardString,
                        source: "clipboard",
                        capturedAt: Date(),
                        characterCount: clipboardString.count,
                        wasTruncated: false
                    )
                } else {
                    self.capturedClipboard = nil
                }
            }
            
            // 2. Application Info
            group.addTask { @MainActor in
                self.capturedApplication = await self.activeWindowService.captureApplicationContext()
            }
            
            // 3. Focused Element (Fast, usually no cache needed)
            group.addTask { @MainActor in
                if let info = await self.focusedElementService.getFocusedElementInfo(timeout: 1.0) {
                    if !info.isEmpty {
                        self.capturedFocusedElement = FocusedElementContext(
                            role: info.role,
                            roleDescription: info.roleDescription,
                            title: info.title,
                            description: info.description,
                            placeholderValue: info.placeholderValue,
                            valueSnippet: info.value,
                            textBeforeCursor: info.textBeforeCursor,
                            textAfterCursor: info.textAfterCursor,
                            nearbyLabels: info.nearbyLabels,
                            capturedAt: Date()
                        )
                    } else {
                        self.capturedFocusedElement = nil
                    }
                } else {
                    self.capturedFocusedElement = nil
                }
            }
            
            // 4. Selected Files (Fast)
            group.addTask { @MainActor in
                let files = await self.selectedFileService.getSelectedFinderFiles(timeout: 2.0)
                self.capturedFiles = !files.isEmpty ? files : nil
            }
            
            // 5. Calendar (Cacheable)
            group.addTask { @MainActor in
                // Check Cache
                if let cached = self.cacheManager.getCalendarContext() {
                    self.capturedCalendar = cached
                    return
                }
                
                // Fetch
                if CalendarService.shared.isAuthorized {
                    let events = await self.calendarService.getUpcomingEvents(timeout: 2.0)
                    if !events.isEmpty {
                        let context = CalendarContext(upcomingEvents: events)
                        self.capturedCalendar = context
                        self.cacheManager.cacheCalendarContext(context)
                    } else {
                        self.capturedCalendar = nil
                    }
                } else {
                    self.capturedCalendar = nil
                }
            }
            
            // 6. Browser Content (Cacheable, Heavy)
            group.addTask { @MainActor in
                // We need the URL to validate the cache accurately.
                // The URL is captured in 'capturedApplication' in step 2.
                // However, these tasks run concurrently, so we can't rely on self.capturedApplication being ready.
                // We will do a lightweight check here.
                
                let currentApp = NSWorkspace.shared.frontmostApplication
                let bundleId = currentApp?.bundleIdentifier ?? ""
                
                // Use BrowserType enum to check if this is a supported browser
                // This ensures consistency with BrowserURLService and BrowserContentService
                // Full content support: Safari, Chrome, Brave, Arc, Edge, Opera, Vivaldi, Orion, Yandex
                // Partial support (title only): Firefox, Zen
                let isSupportedBrowser = BrowserType.allCases.contains { $0.bundleIdentifier == bundleId }
                
                // If not a supported browser, skip
                if !isSupportedBrowser {
                     self.capturedBrowserContent = nil
                     return
                }
                
                // For "Best in Class" accuracy, we MUST validate the URL.
                // If we can't get the URL cheaply, we should arguably skip cache or force fetch.
                // Fortunately, ApplicationContext capture (step 2) fetches the URL.
                // We can re-fetch just the URL here (it's relatively cheap compared to content extraction).
                
                var currentURL: String? = nil
                if let browserType = BrowserType.allCases.first(where: { $0.bundleIdentifier == bundleId }) {
                    currentURL = try? await BrowserURLService.shared.getCurrentURL(from: browserType)
                }
                
                // Check Cache with URL validation
                if let cached = self.cacheManager.getBrowserContext(validatingWith: currentURL) {
                    self.capturedBrowserContent = cached
                    return
                }
                
                // Fetch Fresh
                if let fresh = await self.browserContentService.captureCurrentBrowserContent(timeout: 2.0) {
                    self.capturedBrowserContent = fresh
                    self.cacheManager.cacheBrowserContext(fresh)
                } else {
                    self.capturedBrowserContent = nil
                }
            }
            
            // 7. Screen Capture (Cacheable, Very Heavy)
            group.addTask { @MainActor in
                // Validate against current window title/owner to ensure we don't serve stale OCR
                let currentWindowId = await self.screenCaptureService.getWindowContextIdentifier()
                
                // Check Cache
                if let cached = self.cacheManager.getScreenContext(validatingWith: currentWindowId) {
                    self.capturedScreen = cached
                    return
                }
                
                // Fetch Fresh
                if let fresh = await self.screenCaptureService.captureStructured() {
                    self.capturedScreen = fresh
                    self.cacheManager.cacheScreenContext(fresh)
                } else {
                    self.capturedScreen = nil
                }
            }
        }
    }
    
    /// Build complete context for AI request
    func buildContext(
        settings: AIContextSettings,
        recordingDuration: TimeInterval,
        transcriptionModel: String,
        language: String,
        provider: String,
        model: String,
        promptName: String?
    ) async -> AIContext {
        
        // 1. Gather all potential contexts
        
        // Selected Text (fetched now, usually fast)
        var selectedTextSection: ContextSection? = nil
        if settings.includeSelectedText && AXIsProcessTrusted() {
            if let selectedText = await SelectedTextService.fetchSelectedText(), !selectedText.isEmpty {
                selectedTextSection = ContextSection(
                    content: selectedText,
                    source: "selected_text",
                    capturedAt: Date(),
                    characterCount: selectedText.count,
                    wasTruncated: false
                )
            }
        }
        
        // Retrieve captured state
        let clipboardSection = settings.includeClipboard ? capturedClipboard : nil
        let screenSection = settings.includeScreenCapture ? capturedScreen : nil
        let focusedElementContext = settings.includeFocusedElement ? capturedFocusedElement : nil
        let selectedFilesContext = settings.includeSelectedFiles ? capturedFiles : nil
        let calendarContext = settings.includeCalendar ? capturedCalendar : nil
        let browserContentContext = settings.includeBrowserContent ? capturedBrowserContent : nil
        
        // Populate pageTitle from browser content if available (fixes always-nil pageTitle issue)
        var applicationContext = settings.includeApplicationContext ? capturedApplication : nil
        if let app = applicationContext,
           app.isBrowser,
           let browserContent = browserContentContext {
            applicationContext = ApplicationContext(
                name: app.name,
                bundleIdentifier: app.bundleIdentifier,
                isBrowser: app.isBrowser,
                currentURL: app.currentURL ?? (browserContent.url.isEmpty ? nil : browserContent.url),
                pageTitle: browserContent.title.isEmpty ? nil : browserContent.title
            )
        }
        
        // Vocabulary
        let vocabulary = customVocabularyService.getCustomVocabulary().components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Temporal & Session & PowerMode & UserBio (Low token usage, pass through)
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        let temporalContext = TemporalContext(
            date: dateFormatter.string(from: now),
            time: timeFormatter.string(from: now),
            dayOfWeek: Calendar.current.component(.weekday, from: now).description,
            timezone: TimeZone.current.identifier,
            isWeekend: Calendar.current.isDateInWeekend(now)
        )
        
        let sessionContext = SessionContext(
            recordingDuration: recordingDuration,
            transcriptionModel: transcriptionModel,
            language: language,
            isEnhancementEnabled: true,
            promptName: promptName
        )
        
        var conversationContext: ConversationContext? = nil
        if settings.includeConversationHistory, let historyService = conversationHistoryService {
            let history = historyService.getRecentTranscriptions(
                windowSeconds: settings.conversationWindowMinutes * 60,
                maxItems: settings.maxConversationItems
            )
            if !history.isEmpty {
                conversationContext = ConversationContext(
                    recentTranscriptions: history,
                    windowSeconds: settings.conversationWindowMinutes * 60
                )
            }
        }
        
        let powerMode = PowerModeManager.shared.currentActiveConfiguration.map { config in
            PowerModeContext(
                configName: config.name,
                emoji: config.emoji,
                matchedBy: "unknown",
                matchedPattern: nil
            )
        }
        
        let userBio = !settings.userBio.isEmpty ? settings.userBio : nil
        
        // 2. Apply Token Budget
        // We convert bulky items to ContextSection for the budget manager, then map back
        
        var sectionsToBudget: [ContextSection] = []
        
        if let s = selectedTextSection { sectionsToBudget.append(s) }
        if let c = clipboardSection { sectionsToBudget.append(c) }
        
        if let s = screenSection, let ocr = s.ocrText {
            sectionsToBudget.append(ContextSection(
                content: ocr,
                source: "screen_capture",
                capturedAt: s.capturedAt,
                characterCount: ocr.count,
                wasTruncated: s.wasTruncated
            ))
        }
        
        if let b = browserContentContext {
            sectionsToBudget.append(ContextSection(
                content: b.contentSnippet,
                source: "browser_content", // Must match enum key or manual mapping
                capturedAt: Date(), // Approximate
                characterCount: b.contentSnippet.count,
                wasTruncated: false
            ))
        }
        
        if let f = selectedFilesContext {
            let fileListString = f.map { $0.formattedDescription }.joined(separator: "\n")
            sectionsToBudget.append(ContextSection(
                content: fileListString,
                source: "selected_files",
                capturedAt: Date(),
                characterCount: fileListString.count,
                wasTruncated: false
            ))
        }
        
        if let c = conversationContext {
            let historyString = c.recentTranscriptions.map { $0.text }.joined(separator: "\n")
            sectionsToBudget.append(ContextSection(
                content: historyString,
                source: "conversation_history",
                capturedAt: Date(),
                characterCount: historyString.count,
                wasTruncated: false
            ))
        }
        
        let budget = TokenBudget(provider: provider, model: model)
        let budgetedSections = tokenBudgetManager.fitToBudget(
            sections: sectionsToBudget,
            priorities: settings.contextPriorities,
            budget: budget.availableForContext
        )
        
        // 3. Re-assemble after budgeting
        
        let finalSelectedText = budgetedSections.first(where: { $0.source == "selected_text" })
        let finalClipboard = budgetedSections.first(where: { $0.source == "clipboard" })
        
        // Handle Conversation History truncation
        // If it was removed from budget, we drop it. If present (even truncated), we might keep the original list?
        // Actually, if budget truncated it, the string content is truncated.
        // We can't easily map back to [TranscriptionSummary] from a truncated string.
        // Strategy: If "conversation_history" is missing from budgetedSections, drop it.
        // If present, keep the original context (assuming it's small enough or the truncation was minor).
        // Since we pre-truncate individual items to 200 chars, the risk is low.
        var finalHistory = conversationContext
        if budgetedSections.first(where: { $0.source == "conversation_history" }) == nil && conversationContext != nil {
            finalHistory = nil // Dropped by budget
        }
        
        // Handle Screen Capture truncation
        var finalScreen = screenSection
        if let screenBudgeted = budgetedSections.first(where: { $0.source == "screen_capture" }) {
            finalScreen = ScreenCaptureContext(
                windowTitle: screenSection?.windowTitle ?? "",
                applicationName: screenSection?.applicationName ?? "",
                ocrText: screenBudgeted.content,
                capturedAt: screenSection?.capturedAt ?? Date(),
                wasTruncated: screenBudgeted.wasTruncated
            )
        } else if screenSection?.ocrText != nil {
            finalScreen = nil // Removed by budget
        }
        
        // Handle Browser Content truncation
        var finalBrowser = browserContentContext
        if let browserBudgeted = budgetedSections.first(where: { $0.source == "browser_content" }) {
            finalBrowser = BrowserContentContext(
                url: browserContentContext?.url ?? "",
                title: browserContentContext?.title ?? "",
                contentSnippet: browserBudgeted.content,
                browserName: browserContentContext?.browserName ?? ""
            )
        } else if browserContentContext != nil {
            finalBrowser = nil // Removed by budget
        }
        
        // Handle Files truncation (if we really have too many files)
        // Note: Re-hydrating [FileContext] from a truncated string is hard. 
        // If truncated, we might just drop it or pass the truncated string?
        // Since FileContext is structured, if the budget removes it, we nil it out. 
        // If it truncates it... we probably lose structure. 
        // Strategy: If "selected_files" is present in budgetedSections, we keep the original list (assuming budget logic didn't mangle it too badly, OR we rely on the fact that file lists are usually small).
        // If TokenBudgetManager truncates, it adds "...[TRUNCATED]".
        // For structured data, we might just accept "all or nothing" or simple truncation.
        // Let's go with: if it exists in budget, keep it. If fully removed, drop it.
        var finalFiles = selectedFilesContext
        if budgetedSections.first(where: { $0.source == "selected_files" }) == nil && selectedFilesContext != nil {
            finalFiles = nil // Dropped
        }
        
        return AIContext(
            selectedText: finalSelectedText,
            clipboard: finalClipboard,
            screenCapture: finalScreen,
            customVocabulary: vocabulary,
            focusedElement: focusedElementContext,
            selectedFiles: finalFiles,
            browserContent: finalBrowser,
            application: applicationContext,
            calendar: calendarContext,
            temporal: temporalContext,
            session: sessionContext,
            powerMode: powerMode,
            conversationHistory: finalHistory,
            userBio: userBio,
            capturedAt: Date()
        )
    }
}
