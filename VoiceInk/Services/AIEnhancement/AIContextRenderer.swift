import Foundation

class AIContextRenderer {
    /// Renders full context to XML string
    func render(_ context: AIContext) -> String {
        var sections: [String] = []
        
        // Power Mode context (NEW - Highest level context)
        if let powerMode = context.powerMode {
            sections.append(renderPowerModeContext(powerMode))
        }
        
        // User Context (NEW - Critical for persona)
        if let userBio = context.userBio {
            sections.append("<USER_CONTEXT>\n\(userBio)\n</USER_CONTEXT>")
        }
        
        // Application context (NEW)
        if let app = context.application {
            sections.append(renderApplicationContext(app))
        }
        
        // Focused Element Context (NEW - Intent awareness)
        if let focused = context.focusedElement {
            sections.append(renderFocusedElementContext(focused))
        }
        
        // Selected Files Context (NEW - File awareness)
        if let files = context.selectedFiles, !files.isEmpty {
            sections.append(renderSelectedFilesContext(files))
        }
        
        // Browser Content (NEW - Web reading)
        if let browser = context.browserContent {
            sections.append(renderBrowserContentContext(browser))
        }
        
        // Calendar context (NEW)
        if let calendar = context.calendar, !calendar.upcomingEvents.isEmpty {
            sections.append(renderCalendarContext(calendar))
        }
        
        // Temporal context (NEW)
        sections.append(renderTemporalContext(context.temporal))
        
        // Session context (NEW)
        sections.append(renderSessionContext(context.session))
        
        // Existing content contexts
        if let selectedText = context.selectedText {
            sections.append("<CURRENTLY_SELECTED_TEXT>\n\(selectedText.content)\n</CURRENTLY_SELECTED_TEXT>")
        }
        
        if let clipboard = context.clipboard {
            sections.append("<CLIPBOARD_CONTEXT>\n\(clipboard.content)\n</CLIPBOARD_CONTEXT>")
        }
        
        if let screen = context.screenCapture {
            sections.append(renderScreenContext(screen))
        }
        
        if !context.customVocabulary.isEmpty {
            sections.append("<CUSTOM_VOCABULARY>\n\(context.customVocabulary.joined(separator: ", "))\n</CUSTOM_VOCABULARY>")
        }
        
        // Conversation history (NEW)
        if let history = context.conversationHistory {
            sections.append(renderConversationHistory(history))
        }
        
        return sections.joined(separator: "\n\n")
    }
    
    private func renderApplicationContext(_ app: ApplicationContext) -> String {
        var lines = [
            "<APPLICATION_CONTEXT>",
            "Active Application: \(app.name)",
            "Bundle ID: \(app.bundleIdentifier)"
        ]
        if let url = app.currentURL {
            lines.append("Current URL: \(url)")
        }
        lines.append("</APPLICATION_CONTEXT>")
        return lines.joined(separator: "\n")
    }
    
    private func renderFocusedElementContext(_ focused: FocusedElementContext) -> String {
        var lines = [
            "<INPUT_FIELD_CONTEXT>",
            "UI Element Role: \(focused.roleDescription) (\(focused.role))"
        ]
        
        if let title = focused.title, !title.isEmpty {
            lines.append("Title: \(title)")
        }
        
        if let desc = focused.description, !desc.isEmpty {
            lines.append("Description: \(desc)")
        }
        
        if let placeholder = focused.placeholderValue, !placeholder.isEmpty {
            lines.append("Placeholder: \(placeholder)")
        }
        
        if let value = focused.valueSnippet, !value.isEmpty {
            lines.append("Current Value Snippet: \(value)")
        }
        
        if let before = focused.textBeforeCursor, !before.isEmpty {
            lines.append("Text Before Cursor: ...\(before)")
        }
        
        if let after = focused.textAfterCursor, !after.isEmpty {
            lines.append("Text After Cursor: \(after)...")
        }
        
        if !focused.nearbyLabels.isEmpty {
            lines.append("Nearby Labels: \(focused.nearbyLabels.joined(separator: ", "))")
        }
        
        lines.append("</INPUT_FIELD_CONTEXT>")
        return lines.joined(separator: "\n")
    }
    
    private func renderBrowserContentContext(_ browser: BrowserContentContext) -> String {
        """
        <BROWSER_CONTENT_CONTEXT>
        Page Title: \(browser.title)
        URL: \(browser.url)
        Browser: \(browser.browserName)
        
        Content Snippet:
        \(browser.contentSnippet)
        </BROWSER_CONTENT_CONTEXT>
        """
    }
    
    private func renderSelectedFilesContext(_ files: [FileContext]) -> String {
        var lines = ["<SELECTED_FILES_CONTEXT>"]
        for file in files {
            lines.append(file.formattedDescription)
        }
        lines.append("</SELECTED_FILES_CONTEXT>")
        return lines.joined(separator: "\n")
    }
    
    private func renderCalendarContext(_ calendar: CalendarContext) -> String {
        var lines = ["<CALENDAR_CONTEXT>"]
        for event in calendar.upcomingEvents {
            lines.append(event.formattedDescription)
        }
        lines.append("</CALENDAR_CONTEXT>")
        return lines.joined(separator: "\n")
    }
    
    private func renderTemporalContext(_ temporal: TemporalContext) -> String {
        """
        <TEMPORAL_CONTEXT>
        Date: \(temporal.date) (\(temporal.dayOfWeek))
        Time: \(temporal.time) \(temporal.timezone)
        </TEMPORAL_CONTEXT>
        """
    }
    
    private func renderSessionContext(_ session: SessionContext) -> String {
        """
        <SESSION_CONTEXT>
        Recording Duration: \(Int(session.recordingDuration))s
        Transcription Model: \(session.transcriptionModel)
        Language: \(session.language)
        </SESSION_CONTEXT>
        """
    }
    
    private func renderPowerModeContext(_ powerMode: PowerModeContext) -> String {
        """
        <POWER_MODE>
        Active Config: \(powerMode.emoji) \(powerMode.configName)
        Matched By: \(powerMode.matchedBy)
        </POWER_MODE>
        """
    }
    
    private func renderScreenContext(_ screen: ScreenCaptureContext) -> String {
        var content = """
        <CURRENT_WINDOW_CONTEXT>
        Window Title: \(screen.windowTitle)
        Application: \(screen.applicationName)
        """
        
        if let ocr = screen.ocrText {
            content += "\n\nExtracted Text:\n\(ocr)"
        } else {
            content += "\n\n(No text extracted)"
        }
        
        content += "\n</CURRENT_WINDOW_CONTEXT>"
        return content
    }
    
    private func renderConversationHistory(_ history: ConversationContext) -> String {
        var lines = ["<RECENT_CONVERSATION>"]
        for (index, item) in history.recentTranscriptions.enumerated() {
            lines.append("[\(index + 1)] \(item.text)")
        }
        lines.append("</RECENT_CONVERSATION>")
        return lines.joined(separator: "\n")
    }
}
