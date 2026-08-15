# Additional Quality of Life Improvements for VoiceInk

**Date:** December 7, 2025  
**Status:** New Enhancement Suggestions  
**Type:** Beyond Existing QOL Documentation

---

## Executive Summary

This document identifies **new** quality of life improvements not covered in existing QOL documentation. These suggestions focus on power user features, workflow efficiency, and advanced functionality that would significantly enhance the VoiceInk experience.

**Analysis Note:** The following features are already implemented or documented:
- ✅ Recording duration indicator
- ✅ Enhanced status display
- ✅ Visible cancel button
- ✅ Keyboard shortcut cheat sheet
- ✅ Structured logging (AppLogger)
- ✅ Audio level monitoring
- ✅ Export format options (CSV, JSON, TXT)
- ✅ Retry transcription button
- ✅ Waveform visualization in audio player
- ✅ **Quick Rules** (Smart Auto-Correct) - **NEWLY IMPLEMENTED** 🎉

---

## New Enhancement Categories

### 1. 🗑️ Undo & Recovery Features

#### 🔴 Critical: Recently Deleted / Trash System
**Issue:** Accidental deletions are permanent with no recovery option.

**Proposed Solution:**
```swift
// Add "deleted" flag to Transcription model
@Model
class Transcription {
    // ... existing properties
    var isDeleted: Bool = false
    var deletedAt: Date?
}

// Soft delete implementation
func softDeleteTranscription(_ transcription: Transcription) {
    transcription.isDeleted = true
    transcription.deletedAt = Date()
    try? modelContext.save()
}

// Trash view
struct TrashView: View {
    @Query(filter: #Predicate<Transcription> { $0.isDeleted == true })
    private var deletedTranscriptions: [Transcription]
    
    var body: some View {
        VStack {
            // List deleted transcriptions
            ForEach(deletedTranscriptions) { transcription in
                TranscriptionCard(transcription: transcription)
                    .overlay(
                        Text("Deleted \(formatRelativeTime(transcription.deletedAt))")
                            .foregroundColor(.red)
                    )
            }
            
            HStack {
                Button("Restore Selected") { restoreSelected() }
                Button("Empty Trash") { emptyTrash() }
            }
        }
    }
}

// Auto-cleanup after 30 days
class TrashCleanupService {
    func cleanOldItems() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let predicate = #Predicate<Transcription> { transcription in
            transcription.isDeleted && (transcription.deletedAt ?? Date.distantPast) < thirtyDaysAgo
        }
        // Permanently delete old items
    }
}
```

**Benefits:**
- Recover from accidental deletions
- 30-day safety window
- Batch restore operations
- Peace of mind for users

---

### 2. 📁 File Management Features

#### 🔴 Critical: Drag & Drop Audio File Transcription
**Issue:** Users must use menu navigation to transcribe existing audio files.

**Proposed Solution:**
```swift
// Add drop zone to main window
struct ContentView: View {
    @State private var isDragOver = false
    
    var body: some View {
        TabView {
            // ... existing tabs
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .overlay(
            isDragOver ? DropOverlay() : nil
        )
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      isAudioFile(url) else { return }
                
                Task { @MainActor in
                    await transcribeDroppedFile(url)
                }
            }
        }
        return true
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.1)
            VStack(spacing: 16) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 64))
                Text("Drop audio files to transcribe")
                    .font(.title2)
                Text("Supports WAV, MP3, M4A, FLAC")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .transition(.opacity)
    }
}
```

**Benefits:**
- Faster workflow for file transcription
- Intuitive file handling
- Visual feedback during drag
- Multi-file support

---

#### 🟠 High: Batch Audio File Transcription
**Issue:** Processing multiple audio files requires transcribing one at a time.

**Proposed Solution:**
```swift
// Batch transcription queue
@MainActor
class BatchTranscriptionQueue: ObservableObject {
    @Published var queue: [BatchJob] = []
    @Published var isProcessing = false
    @Published var currentJob: BatchJob?
    @Published var progress: Double = 0
    
    struct BatchJob: Identifiable {
        let id = UUID()
        let url: URL
        var status: Status = .pending
        var transcription: Transcription?
        var error: Error?
        
        enum Status {
            case pending, processing, completed, failed
        }
    }
    
    func addFiles(_ urls: [URL]) {
        let jobs = urls.map { BatchJob(url: $0) }
        queue.append(contentsOf: jobs)
        
        if !isProcessing {
            Task { await processQueue() }
        }
    }
    
    func processQueue() async {
        isProcessing = true
        
        for (index, job) in queue.enumerated() {
            guard job.status == .pending else { continue }
            
            currentJob = job
            queue[index].status = .processing
            
            do {
                let transcription = try await transcribeFile(job.url)
                queue[index].status = .completed
                queue[index].transcription = transcription
            } catch {
                queue[index].status = .failed
                queue[index].error = error
            }
            
            progress = Double(index + 1) / Double(queue.count)
        }
        
        isProcessing = false
        currentJob = nil
        
        // Show completion notification
        NotificationManager.shared.showNotification(
            title: "Batch transcription complete",
            subtitle: "\(completedCount) files processed successfully"
        )
    }
}

// Batch transcription UI
struct BatchTranscriptionView: View {
    @StateObject private var batchQueue = BatchTranscriptionQueue()
    
    var body: some View {
        VStack {
            // Progress indicator
            if batchQueue.isProcessing {
                ProgressView(value: batchQueue.progress)
                Text("Processing \(batchQueue.currentJob?.url.lastPathComponent ?? "")")
            }
            
            // Queue list
            List(batchQueue.queue) { job in
                HStack {
                    Image(systemName: statusIcon(job.status))
                    Text(job.url.lastPathComponent)
                    Spacer()
                    Text(job.status.description)
                }
            }
            
            // Controls
            HStack {
                Button("Add Files") {
                    selectAudioFiles()
                }
                Button("Clear Completed") {
                    batchQueue.clearCompleted()
                }
                Button("Cancel") {
                    batchQueue.cancel()
                }
                .disabled(!batchQueue.isProcessing)
            }
        }
    }
}
```

**Benefits:**
- Process multiple files efficiently
- Background processing
- Progress tracking
- Error handling per file

---

### 3. 🏷️ Organization Features

#### 🟠 High: Transcription Tags & Notes
**Issue:** No way to categorize or add context to transcriptions.

**Proposed Solution:**
```swift
// Add to Transcription model
@Model
class Transcription {
    // ... existing properties
    var tags: [String] = []
    var notes: String?
    var isPinned: Bool = false
    var color: String? // For color coding
}

// Tag management
struct TagEditorView: View {
    @Binding var tags: [String]
    @State private var newTag = ""
    @State private var suggestions: [String] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag input with autocomplete
            HStack {
                TextField("Add tag", text: $newTag)
                    .onSubmit { addTag() }
                Button("Add") { addTag() }
            }
            
            // Tag suggestions from existing tags
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                tags.append(suggestion)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            
            // Current tags
            FlowLayout {
                ForEach(tags, id: \.self) { tag in
                    TagChip(tag: tag) {
                        tags.removeAll { $0 == tag }
                    }
                }
            }
        }
    }
}

// Tag filtering in history
struct TagFilterView: View {
    @Binding var selectedTags: Set<String>
    let allTags: [String]
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(allTags, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(
                        get: { selectedTags.contains(tag) },
                        set: { if $0 { selectedTags.insert(tag) } else { selectedTags.remove(tag) }}
                    ))
                    .toggleStyle(.button)
                }
            }
        }
    }
}

// Notes section in expanded card
struct NotesSection: View {
    @Binding var notes: String?
    @State private var isEditing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
            }
            
            if isEditing {
                TextEditor(text: Binding(
                    get: { notes ?? "" },
                    set: { notes = $0.isEmpty ? nil : $0 }
                ))
                .frame(height: 100)
            } else if let notes = notes {
                Text(notes)
                    .foregroundColor(.secondary)
            } else {
                Text("No notes")
                    .foregroundColor(.tertiary)
                    .italic()
            }
        }
    }
}
```

**Benefits:**
- Organize transcriptions by topic
- Search by tags
- Add context with notes
- Visual color coding

---

#### 🟠 High: Pin Favorite Transcriptions
**Issue:** Important transcriptions get lost in history.

**Proposed Solution:**
```swift
// Update history view to show pinned first
struct TranscriptionHistoryView: View {
    @Query(filter: #Predicate<Transcription> { $0.isPinned == true && $0.isDeleted == false })
    private var pinnedTranscriptions: [Transcription]
    
    @Query(filter: #Predicate<Transcription> { $0.isPinned == false && $0.isDeleted == false })
    private var regularTranscriptions: [Transcription]
    
    var body: some View {
        ScrollView {
            if !pinnedTranscriptions.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedTranscriptions) { transcription in
                        TranscriptionCard(transcription: transcription)
                            .overlay(
                                Image(systemName: "pin.fill")
                                    .foregroundColor(.yellow)
                                    .padding(8),
                                alignment: .topTrailing
                            )
                    }
                }
            }
            
            Section("All Transcriptions") {
                ForEach(regularTranscriptions) { transcription in
                    TranscriptionCard(transcription: transcription)
                }
            }
        }
    }
}

// Pin toggle in context menu
contextMenu {
    Button {
        transcription.isPinned.toggle()
    } label: {
        Label(
            transcription.isPinned ? "Unpin" : "Pin",
            systemImage: transcription.isPinned ? "pin.slash" : "pin"
        )
    }
    // ... other menu items
}
```

**Benefits:**
- Keep important transcriptions accessible
- Quick access to frequently referenced content
- Visual distinction for pinned items

---

### 4. ⌨️ Keyboard Navigation & Shortcuts

#### 🔴 Critical: Full Keyboard Navigation in History
**Issue:** Mouse required for most history operations.

**Proposed Solution:**
```swift
struct TranscriptionHistoryView: View {
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(Array(displayedTranscriptions.enumerated()), id: \.element.id) { index, transcription in
                    TranscriptionCard(transcription: transcription)
                        .focused($isFocused, equals: true)
                        .background(selectedIndex == index ? Color.accentColor.opacity(0.1) : Color.clear)
                }
            }
        }
        .onAppear { isFocused = true }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(displayedTranscriptions.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            toggleExpand(displayedTranscriptions[selectedIndex])
            return .handled
        }
        .onKeyPress(.space) {
            toggleSelection(displayedTranscriptions[selectedIndex])
            return .handled
        }
        .onKeyPress("c", modifiers: .command) {
            copyTranscription(displayedTranscriptions[selectedIndex])
            return .handled
        }
        .onKeyPress(.delete) {
            deleteTranscription(displayedTranscriptions[selectedIndex])
            return .handled
        }
    }
}

// Add keyboard shortcut hints
struct KeyboardShortcutHints: View {
    var body: some View {
        HStack(spacing: 16) {
            ShortcutHint(key: "↑↓", description: "Navigate")
            ShortcutHint(key: "⏎", description: "Expand")
            ShortcutHint(key: "Space", description: "Select")
            ShortcutHint(key: "⌘C", description: "Copy")
            ShortcutHint(key: "⌫", description: "Delete")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
```

**Benefits:**
- Faster navigation for power users
- Accessibility improvement
- Reduced mouse dependency
- Professional workflow

---

### 5. 📊 Smart Text Processing

#### ✅ IMPLEMENTED: Quick Rules Feature (formerly "Auto-Correct Common Transcription Errors")
**Status:** Fully implemented - see `QUICK_RULES_IMPLEMENTATION.md`  
**Implementation:** Dictionary Quick Rules with 17 preset rules and custom rule support

**Proposed Solution:**
```swift
// Smart text processor
class SmartTextProcessor {
    struct Rule {
        let pattern: String
        let replacement: String
        let isRegex: Bool
        let isEnabled: Bool
    }
    
    static let defaultRules: [Rule] = [
        Rule(pattern: "gonna", replacement: "going to", isRegex: false, isEnabled: true),
        Rule(pattern: "wanna", replacement: "want to", isRegex: false, isEnabled: true),
        Rule(pattern: "kinda", replacement: "kind of", isRegex: false, isEnabled: true),
        Rule(pattern: "sorta", replacement: "sort of", isRegex: false, isEnabled: true),
        Rule(pattern: "\\b(\\w+)\\s+\\1\\b", replacement: "$1", isRegex: true, isEnabled: true), // Remove duplicates
        Rule(pattern: "\\s+", replacement: " ", isRegex: true, isEnabled: true), // Multiple spaces
        Rule(pattern: "^\\s+|\\s+$", replacement: "", isRegex: true, isEnabled: true), // Trim
    ]
    
    func process(_ text: String, rules: [Rule]) -> String {
        var processed = text
        
        for rule in rules where rule.isEnabled {
            if rule.isRegex {
                if let regex = try? NSRegularExpression(pattern: rule.pattern) {
                    let range = NSRange(processed.startIndex..., in: processed)
                    processed = regex.stringByReplacingMatches(
                        in: processed,
                        range: range,
                        withTemplate: rule.replacement
                    )
                }
            } else {
                processed = processed.replacingOccurrences(
                    of: rule.pattern,
                    with: rule.replacement,
                    options: .caseInsensitive
                )
            }
        }
        
        return processed
    }
}

// Settings UI
struct SmartProcessingSettings: View {
    @AppStorage("enableSmartProcessing") private var enabled = false
    @State private var rules: [SmartTextProcessor.Rule] = SmartTextProcessor.defaultRules
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Enable Smart Text Processing", isOn: $enabled)
            
            Text("Automatically correct common transcription errors")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if enabled {
                List {
                    ForEach(rules.indices, id: \.self) { index in
                        HStack {
                            Toggle("", isOn: $rules[index].isEnabled)
                            Text(rules[index].pattern)
                            Text("→")
                                .foregroundColor(.secondary)
                            Text(rules[index].replacement)
                        }
                    }
                }
            }
        }
    }
}
```

**Benefits:**
- Cleaner transcriptions automatically
- Customizable rules
- Reduce manual editing
- Professional output

---

### 6. 🔍 Advanced Search & Filtering

#### 🟠 High: Global Search Across All Features
**Issue:** Search limited to transcription history only.

**Proposed Solution:**
```swift
// Global search view
struct GlobalSearchView: View {
    @State private var searchText = ""
    @State private var searchResults: SearchResults?
    
    struct SearchResults {
        var transcriptions: [Transcription]
        var powerModes: [PowerModeConfig]
        var prompts: [CustomPrompt]
        var wordReplacements: [WordReplacement]
    }
    
    var body: some View {
        VStack {
            // Search bar
            SearchBar(text: $searchText, onSubmit: performSearch)
            
            if let results = searchResults {
                List {
                    if !results.transcriptions.isEmpty {
                        Section("Transcriptions (\(results.transcriptions.count))") {
                            ForEach(results.transcriptions) { transcription in
                                TranscriptionRow(transcription: transcription, searchTerm: searchText)
                            }
                        }
                    }
                    
                    if !results.powerModes.isEmpty {
                        Section("Power Modes (\(results.powerModes.count))") {
                            ForEach(results.powerModes) { mode in
                                PowerModeRow(mode: mode)
                            }
                        }
                    }
                    
                    if !results.prompts.isEmpty {
                        Section("Prompts (\(results.prompts.count))") {
                            ForEach(results.prompts) { prompt in
                                PromptRow(prompt: prompt)
                            }
                        }
                    }
                    
                    if !results.wordReplacements.isEmpty {
                        Section("Dictionary (\(results.wordReplacements.count))") {
                            ForEach(results.wordReplacements) { replacement in
                                WordReplacementRow(replacement: replacement)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func performSearch() {
        // Search across all features
        let transcriptions = searchTranscriptions(searchText)
        let powerModes = searchPowerModes(searchText)
        let prompts = searchPrompts(searchText)
        let wordReplacements = searchDictionary(searchText)
        
        searchResults = SearchResults(
            transcriptions: transcriptions,
            powerModes: powerModes,
            prompts: prompts,
            wordReplacements: wordReplacements
        )
    }
}

// Add to menu bar
Button("Global Search") {
    showGlobalSearch = true
}
.keyboardShortcut("f", modifiers: [.command, .shift])
```

**Benefits:**
- Find anything quickly
- Cross-feature search
- Better discoverability
- Power user feature

---

### 7. 🎨 Customization Features

#### 🟡 Medium: Transcription Templates
**Issue:** Users repeatedly configure the same settings for different use cases.

**Proposed Solution:**
```swift
// Transcription template
struct TranscriptionTemplate: Codable, Identifiable {
    let id: UUID
    var name: String
    var emoji: String
    
    // Settings
    var transcriptionModel: String
    var aiProvider: String?
    var aiModel: String?
    var prompt: String?
    var enhancementEnabled: Bool
    var useClipboardContext: Bool
    var useScreenCapture: Bool
    var language: String?
    
    // Quick access
    var keyboardShortcut: KeyEquivalent?
}

// Template manager
@MainActor
class TemplateManager: ObservableObject {
    @Published var templates: [TranscriptionTemplate] = []
    
    static let presets: [TranscriptionTemplate] = [
        TranscriptionTemplate(
            name: "Meeting Notes",
            emoji: "📝",
            transcriptionModel: "whisper-large-v3",
            enhancementEnabled: true,
            prompt: "Format as structured meeting notes"
        ),
        TranscriptionTemplate(
            name: "Quick Memo",
            emoji: "⚡️",
            transcriptionModel: "whisper-base",
            enhancementEnabled: false
        ),
        TranscriptionTemplate(
            name: "Code Documentation",
            emoji: "💻",
            transcriptionModel: "whisper-large-v3",
            enhancementEnabled: true,
            prompt: "Format as technical documentation with code examples"
        )
    ]
    
    func applyTemplate(_ template: TranscriptionTemplate) {
        // Apply all settings from template
        whisperState.setModel(template.transcriptionModel)
        enhancementService.isEnhancementEnabled = template.enhancementEnabled
        // ... apply other settings
    }
}

// Quick template picker
struct TemplatePickerView: View {
    @EnvironmentObject var templateManager: TemplateManager
    
    var body: some View {
        Menu {
            ForEach(templateManager.templates) { template in
                Button {
                    templateManager.applyTemplate(template)
                } label: {
                    Label("\(template.emoji) \(template.name)", systemImage: "checkmark")
                }
            }
            
            Divider()
            
            Button("Manage Templates...") {
                showTemplateEditor = true
            }
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                Text("Templates")
            }
        }
    }
}
```

**Benefits:**
- Quick setup for different workflows
- Save time reconfiguring
- Share templates with team
- Standardize processes

---

### 8. 📤 Advanced Export & Integration

#### 🟡 Medium: Custom Export Templates
**Issue:** Export formats are fixed; users need custom formatting.

**Proposed Solution:**
```swift
// Export template engine
struct ExportTemplate: Codable, Identifiable {
    let id: UUID
    var name: String
    var format: String // Handlebars-style template
    var fileExtension: String
    
    static let markdownTemplate = ExportTemplate(
        name: "Markdown",
        format: """
        # {{date}}
        
        {{#if powerMode}}
        **Power Mode:** {{powerMode.emoji}} {{powerMode.name}}
        {{/if}}
        
        ## Original Transcription
        
        {{text}}
        
        {{#if enhancedText}}
        ## Enhanced Version
        
        {{enhancedText}}
        {{/if}}
        
        ---
        
        **Model:** {{modelName}}
        **Duration:** {{duration}}
        """,
        fileExtension: "md"
    )
}

// Template renderer
class ExportTemplateRenderer {
    func render(_ transcriptions: [Transcription], using template: ExportTemplate) -> String {
        // Parse template and replace variables
        var output = ""
        
        for transcription in transcriptions {
            var rendered = template.format
            
            // Replace variables
            rendered = rendered.replacingOccurrences(of: "{{date}}", with: formatDate(transcription.timestamp))
            rendered = rendered.replacingOccurrences(of: "{{text}}", with: transcription.text)
            rendered = rendered.replacingOccurrences(of: "{{enhancedText}}", with: transcription.enhancedText ?? "")
            // ... more replacements
            
            output += rendered + "\n\n"
        }
        
        return output
    }
}

// Template editor
struct ExportTemplateEditor: View {
    @Binding var template: ExportTemplate
    @State private var previewText: String = ""
    
    var body: some View {
        HSplitView {
            // Template editor
            VStack {
                TextField("Template Name", text: $template.name)
                TextField("File Extension", text: $template.fileExtension)
                
                TextEditor(text: $template.format)
                    .font(.system(.body, design: .monospaced))
            }
            
            // Live preview
            VStack {
                Text("Preview")
                    .font(.headline)
                ScrollView {
                    Text(previewText)
                }
            }
        }
        .onChange(of: template.format) { _, _ in
            updatePreview()
        }
    }
}
```

**Benefits:**
- Flexible export formats
- Custom branding
- Integration with specific workflows
- Reusable templates

---

#### 🟡 Medium: App Integration Shortcuts
**Issue:** No easy way to send transcriptions to other apps.

**Proposed Solution:**
```swift
// App integration manager
struct AppIntegration: Identifiable {
    let id: UUID
    var name: String
    var bundleID: String
    var action: IntegrationAction
    
    enum IntegrationAction {
        case copyAndOpen // Copy text, open app
        case urlScheme(template: String) // Use URL scheme
        case shortcut(name: String) // Apple Shortcut
    }
}

// Quick actions menu
struct QuickActionsMenu: View {
    let transcription: Transcription
    
    var body: some View {
        Menu {
            Button("Send to Obsidian") {
                sendToObsidian(transcription)
            }
            
            Button("Send to Notion") {
                sendToNotion(transcription)
            }
            
            Button("Create Apple Note") {
                createAppleNote(transcription)
            }
            
            Button("Add to Reminders") {
                addToReminders(transcription)
            }
            
            Divider()
            
            Button("Configure Integrations...") {
                showIntegrationSettings = true
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }
    
    private func sendToObsidian(_ transcription: Transcription) {
        // Use Obsidian URL scheme
        let text = transcription.enhancedText ?? transcription.text
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "obsidian://new?vault=MyVault&content=\(encoded)"
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
```

**Benefits:**
- Seamless workflow integration
- One-click actions
- Customizable per user
- Professional productivity

---

### 9. 🔔 Notification Improvements

#### 🟡 Medium: Notification Center with History
**Issue:** Notifications disappear; no way to review past notifications.

**Proposed Solution:**
```swift
// Notification history
@MainActor
class NotificationHistory: ObservableObject {
    @Published var notifications: [HistoricalNotification] = []
    
    struct HistoricalNotification: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String?
        let type: NotificationType
        let timestamp: Date
        var isRead: Bool = false
    }
    
    func add(_ notification: HistoricalNotification) {
        notifications.insert(notification, at: 0)
        
        // Keep last 50
        if notifications.count > 50 {
            notifications = Array(notifications.prefix(50))
        }
    }
    
    func markAllRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
    }
}

// Notification center view
struct NotificationCenterView: View {
    @EnvironmentObject var notificationHistory: NotificationHistory
    
    var body: some View {
        VStack {
            HStack {
                Text("Notifications")
                    .font(.title2)
                Spacer()
                Button("Mark All Read") {
                    notificationHistory.markAllRead()
                }
            }
            
            List(notificationHistory.notifications) { notification in
                HStack {
                    Image(systemName: notification.type.icon)
                        .foregroundColor(notification.type.color)
                    
                    VStack(alignment: .leading) {
                        Text(notification.title)
                            .fontWeight(notification.isRead ? .regular : .bold)
                        if let subtitle = notification.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text(formatRelativeTime(notification.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .opacity(notification.isRead ? 0.6 : 1.0)
            }
        }
        .padding()
    }
}

// Add to menu bar
Button {
    showNotificationCenter = true
} label: {
    Image(systemName: "bell.fill")
        .overlay(
            notificationHistory.notifications.filter { !$0.isRead }.count > 0 ?
            Badge(count: notificationHistory.notifications.filter { !$0.isRead }.count) : nil
        )
}
```

**Benefits:**
- Review past notifications
- Don't miss important alerts
- Notification history
- Better awareness

---

### 10. 🎯 Power User Features

#### 🟡 Medium: Quick Actions Toolbar (Floating)
**Issue:** Common actions require multiple clicks through menus.

**Proposed Solution:**
```swift
// Floating quick actions toolbar
struct QuickActionsToolbar: View {
    @State private var isExpanded = false
    @State private var position: CGPoint = .init(x: 100, y: 100)
    
    var body: some View {
        VStack(spacing: 0) {
            // Main button
            Button {
                withAnimation(.spring()) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "bolt.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(radius: 4)
            }
            .buttonStyle(.plain)
            
            // Quick action buttons (expanded)
            if isExpanded {
                VStack(spacing: 8) {
                    QuickActionButton(icon: "mic.fill", color: .red) {
                        startRecording()
                    }
                    QuickActionButton(icon: "arrow.clockwise", color: .green) {
                        retryLast()
                    }
                    QuickActionButton(icon: "doc.on.doc", color: .blue) {
                        copyLast()
                    }
                    QuickActionButton(icon: "clock.arrow.circlepath", color: .orange) {
                        openHistory()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .position(position)
        .gesture(
            DragGesture()
                .onChanged { value in
                    position = value.location
                }
        )
    }
}

struct QuickActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(color))
        }
        .buttonStyle(.plain)
    }
}
```

**Benefits:**
- One-click access to common actions
- Customizable position
- Reduced navigation
- Always available

---

## Implementation Priority Matrix

### Immediate Value (Next Sprint)
1. 🗑️ Recently Deleted / Trash System
2. 📁 Drag & Drop Audio Files
3. ⌨️ Full Keyboard Navigation
4. 🏷️ Transcription Tags & Notes

### High Value (Next Month)
5. 📁 Batch Audio File Transcription
6. 🏷️ Pin Favorite Transcriptions
7. ~~📊 Auto-Correct Common Errors~~ ✅ **IMPLEMENTED** (see Quick Rules)
8. 🔍 Global Search

### Enhanced Experience (Next Quarter)
9. 🎨 Transcription Templates
10. 📤 Custom Export Templates
11. 🔔 Notification Center
12. 📤 App Integration Shortcuts

### Power User Features (Future)
13. 🎯 Quick Actions Toolbar
14. 🔄 Advanced filtering & sorting
15. 📊 Usage analytics dashboard
16. 🌐 Cloud sync (optional)

---

## Technical Considerations

### Performance Impact
- **Low**: Tags, notes, pin feature, keyboard navigation
- **Medium**: Drag & drop, notification history, global search
- **High**: Batch transcription, smart text processing

### Complexity
- **Simple**: Pin feature, tags, notification center
- **Moderate**: Drag & drop, keyboard navigation, templates
- **Complex**: Batch transcription, smart processing, app integrations

### User Testing Priority
1. Drag & drop (must be intuitive)
2. Trash system (must prevent data loss)
3. Keyboard navigation (must not conflict)
4. Batch transcription (must handle errors well)

---

## Success Metrics

### User Engagement
- **Adoption Rate**: % of users using new features
- **Frequency**: How often features are used
- **Retention**: Do features reduce churn?

### Productivity
- **Time Saved**: Measure workflow efficiency gains
- **Actions per Session**: Are users accomplishing more?
- **Error Rate**: Reduction in user mistakes

### Satisfaction
- **Feature Requests**: Reduction in related requests
- **Support Tickets**: Fewer issues with workflows
- **User Ratings**: Impact on app store rating

---

## Conclusion

These quality of life improvements focus on **power user workflows** and **advanced productivity features** that complement the existing enhancements already implemented in VoiceInk. The suggestions prioritize:

1. **Recovery & Safety** - Trash system, undo operations
2. **Efficiency** - Drag & drop, batch operations, keyboard navigation
3. **Organization** - Tags, notes, pins, templates
4. **Integration** - Export templates, app shortcuts
5. **Power Features** - Global search, smart processing

Implementing these features would position VoiceInk as a **professional-grade transcription tool** suitable for power users, developers, and content creators who demand advanced functionality and workflow optimization.

---

**Last Updated:** December 7, 2025  
**Author:** AI Analysis  
**Status:** Ready for Review & Discussion
