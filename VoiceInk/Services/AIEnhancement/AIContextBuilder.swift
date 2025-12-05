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
        activeWindowService: ActiveWindowService = ActiveWindowService.shared,
        focusedElementService: FocusedElementService = FocusedElementService.shared,
        selectedFileService: SelectedFileService = SelectedFileService.shared,
        calendarService: CalendarService = CalendarService.shared,
        browserContentService: BrowserContentService = BrowserContentService.shared,
        modelContext: ModelContext? = nil
    ) {
        self.screenCaptureService = screenCaptureService ?? ScreenCaptureService()
        self.customVocabularyService = customVocabularyService
        self.activeWindowService = activeWindowService
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
        // Capture clipboard
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
        
        // Capture application info
        self.capturedApplication = await activeWindowService.captureApplicationContext()
        
        // Capture focused element (UI intent)
        if let info = focusedElementService.getFocusedElementInfo(), !info.isEmpty {
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
        
        // Capture selected files (Finder)
        let files = await selectedFileService.getSelectedFinderFiles()
        self.capturedFiles = !files.isEmpty ? files : nil
        
        // Capture calendar (if authorized and relevant)
        if CalendarService.shared.isAuthorized {
            let events = await calendarService.getUpcomingEvents()
            self.capturedCalendar = !events.isEmpty ? CalendarContext(upcomingEvents: events) : nil
        } else {
            self.capturedCalendar = nil
        }
        
        // Capture browser content
        self.capturedBrowserContent = await browserContentService.captureCurrentBrowserContent()
        
        // Capture screen content (OCR)
        // Note: This is resource intensive, so we do it last in this block
        self.capturedScreen = await screenCaptureService.captureStructured()
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
        
        // Selected Text (fetched now)
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
        
        // Clipboard (from capture)
        let clipboardSection = settings.includeClipboard ? capturedClipboard : nil
        
        // Screen (from capture)
        let screenSection = settings.includeScreenCapture ? capturedScreen : nil
        
        // Application (from capture)
        let applicationContext = settings.includeApplicationContext ? capturedApplication : nil
        
        // Focused Element (from capture)
        let focusedElementContext = settings.includeFocusedElement ? capturedFocusedElement : nil
        
        // Selected Files (from capture)
        let selectedFilesContext = settings.includeSelectedFiles ? capturedFiles : nil
        
        // Calendar (from capture)
        let calendarContext = settings.includeCalendar ? capturedCalendar : nil
        
        // Browser Content (from capture)
        let browserContentContext = settings.includeBrowserContent ? capturedBrowserContent : nil
        
        // Vocabulary
        let vocabulary = customVocabularyService.getCustomVocabulary().components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Temporal
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        let temporalContext = TemporalContext(
            date: dateFormatter.string(from: now),
            time: timeFormatter.string(from: now),
            dayOfWeek: Calendar.current.component(.weekday, from: now).description, // Simplified
            timezone: TimeZone.current.identifier,
            isWeekend: Calendar.current.isDateInWeekend(now)
        )
        
        // Session
        let sessionContext = SessionContext(
            recordingDuration: recordingDuration,
            transcriptionModel: transcriptionModel,
            language: language,
            isEnhancementEnabled: true,
            promptName: promptName
        )
        
        // Conversation History
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
        
        // Power Mode
        let powerMode = PowerModeManager.shared.currentActiveConfiguration.map { config in
            PowerModeContext(
                configName: config.name,
                emoji: config.emoji,
                matchedBy: "unknown", // Logic to determine match type could be added here
                matchedPattern: nil
            )
        }
        
        // User Bio
        let userBio = !settings.userBio.isEmpty ? settings.userBio : nil
        
        // 2. Apply Token Budget
        // For now, we only budget "heavy" text sections: selectedText, clipboard, screen
        
        var sectionsToBudget: [ContextSection] = []
        if let s = selectedTextSection { sectionsToBudget.append(s) }
        if let c = clipboardSection { sectionsToBudget.append(c) }
        if let s = screenSection {
            // Convert ScreenCaptureContext to ContextSection for budgeting purposes
            if let ocr = s.ocrText {
                sectionsToBudget.append(ContextSection(
                    content: ocr,
                    source: "screen_capture",
                    capturedAt: s.capturedAt,
                    characterCount: ocr.count,
                    wasTruncated: s.wasTruncated
                ))
            }
        }
        
        let budget = TokenBudget(provider: provider, model: model)
        let budgetedSections = tokenBudgetManager.fitToBudget(
            sections: sectionsToBudget,
            priorities: settings.contextPriorities,
            budget: budget.availableForContext
        )
        
        // Re-assemble after budgeting
        // Map back to specific properties
        let finalSelectedText = budgetedSections.first(where: { $0.source == "selected_text" })
        let finalClipboard = budgetedSections.first(where: { $0.source == "clipboard" })
        
        var finalScreen = screenSection
        if let screenBudgeted = budgetedSections.first(where: { $0.source == "screen_capture" }) {
            // Update OCR text with potentially truncated version
            finalScreen = ScreenCaptureContext(
                windowTitle: screenSection?.windowTitle ?? "",
                applicationName: screenSection?.applicationName ?? "",
                ocrText: screenBudgeted.content,
                capturedAt: screenSection?.capturedAt ?? Date(),
                wasTruncated: screenBudgeted.wasTruncated
            )
        } else if screenSection?.ocrText != nil {
            // It was removed entirely by budget
            finalScreen = nil
        }
        
        return AIContext(
            selectedText: finalSelectedText,
            clipboard: finalClipboard,
            screenCapture: finalScreen,
            customVocabulary: vocabulary,
            focusedElement: focusedElementContext,
            selectedFiles: selectedFilesContext,
            browserContent: browserContentContext,
            application: applicationContext,
            calendar: calendarContext,
            temporal: temporalContext,
            session: sessionContext,
            powerMode: powerMode,
            conversationHistory: conversationContext,
            userBio: userBio,
            capturedAt: Date()
        )
    }
}
