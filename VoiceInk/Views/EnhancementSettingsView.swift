import SwiftUI
import UniformTypeIdentifiers

struct EnhancementSettingsView: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var isEditingPrompt = false
    @State private var isSettingsExpanded = true
    @State private var selectedPromptForEdit: CustomPrompt?
    @AppStorage("enableAIEnhancementFeatures") private var enableAIEnhancementFeatures = false
    
    /// Formats the timeout value for display (e.g., "30s" or "2m 30s")
    private func formatTimeout(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds >= 60 {
            let minutes = totalSeconds / 60
            let remainingSeconds = totalSeconds % 60
            if remainingSeconds == 0 {
                return "\(minutes)m"
            }
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(totalSeconds)s"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: VoiceInkSpacing.xl) {
                // Main Settings Sections
                VStack(spacing: VoiceInkSpacing.lg) {
                    // Enable/Disable Toggle Section
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Enable Enhancement")
                                        .voiceInkHeadline()
                                    
                                    InfoTip(
                                        title: "AI Enhancement",
                                        message: "AI enhancement lets you pass the transcribed audio through LLMS to post-process using different prompts suitable for different use cases like e-mails, summary, writing, etc.",
                                        learnMoreURL: "https://www.youtube.com/@tryvoiceink/videos"
                                    )
                                }
                                
                                Text("Turn on AI-powered enhancement features")
                                    .voiceInkCaptionStyle()
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $enhancementService.isEnhancementEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: VoiceInkTheme.Palette.accent))
                                .labelsHidden()
                                .scaleEffect(1.2)
                        }
                        
                        // Context Settings
                        ContextSettingsView(settings: $enhancementService.contextSettings)
                            .disabled(!enhancementService.isEnhancementEnabled)
                            .opacity(enhancementService.isEnhancementEnabled ? 1 : 0.6)
                    }
                    .padding(VoiceInkSpacing.lg)
                    .voiceInkCardBackground()
                    
                    if enableAIEnhancementFeatures {
                        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                            Text("AI Provider Integration")
                                .voiceInkHeadline()
                            
                            APIKeyManagementView()
                            
                            Divider()
                                .padding(.vertical, VoiceInkSpacing.sm)
                            
                            // Request Timeout Setting
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: VoiceInkSpacing.xs) {
                                    Text("Request Timeout")
                                        .voiceInkSubheadline()
                                        .foregroundStyle(.primary)
                                    
                                    InfoTip(
                                        title: "Request Timeout",
                                        message: "Maximum time to wait for AI enhancement responses. Increase this value for slower connections, complex prompts, or when using models that require more processing time."
                                    )
                                }
                                
                                HStack(spacing: VoiceInkSpacing.md) {
                                    Slider(
                                        value: $enhancementService.requestTimeout,
                                        in: AIEnhancementService.minimumTimeout...AIEnhancementService.maximumTimeout,
                                        step: 5
                                    )
                                    .frame(maxWidth: .infinity)
                                    
                                    Text(formatTimeout(enhancementService.requestTimeout))
                                        .voiceInkCaptionStyle()
                                        .monospacedDigit()
                                        .frame(width: 60, alignment: .trailing)
                                }
                                
                                Text("Default: 30 seconds")
                                    .voiceInkCaptionStyle()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(VoiceInkSpacing.lg)
                        .voiceInkCardBackground()
                    } else {
                        VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                            Label("Local-Only Enhancement", systemImage: "lock.shield")
                                .font(.headline)
                            
                            Text("The community build keeps enhancement providers on-device by default. Enable AI enhancements in Settings to configure cloud providers like OpenAI or Google.")
                                .voiceInkCaptionStyle()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(VoiceInkSpacing.lg)
                        .voiceInkCardBackground()
                    }
                    
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                        Text("Enhancement Prompts & Persona")
                            .voiceInkHeadline()
                        
                        // Personal Context Section (Moved to top of card)
                        VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                            HStack {
                                Label("Global Personal Context", systemImage: "person.text.rectangle")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                
                                InfoTip(
                                    title: "Personal Context",
                                    message: "This bio is persistently saved and sent with EVERY request to all prompts below. Use it to define your role, preferred tone, or specific constraints."
                                )
                            }
                            
                            TextEditor(text: $enhancementService.contextSettings.userBio)
                                .font(.body)
                                .frame(height: 80)
                                .padding(VoiceInkSpacing.sm)
                                .background(VoiceInkTheme.Palette.canvas)
                                .cornerRadius(VoiceInkRadius.small)
                                .overlay(
                                    RoundedRectangle(cornerRadius: VoiceInkRadius.small)
                                        .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                                )
                                .overlay(
                                    Group {
                                        if enhancementService.contextSettings.userBio.isEmpty {
                                            Text("Example: I am a software engineer. I prefer concise bullet points...")
                                                .foregroundColor(.secondary.opacity(0.5))
                                                .padding(VoiceInkSpacing.md)
                                                .allowsHitTesting(false)
                                        }
                                    },
                                    alignment: .topLeading
                                )
                        }
                        
                        Divider()
                            .padding(.vertical, VoiceInkSpacing.sm)
                        
                        // Reorderable prompts grid with drag-and-drop
                        ReorderablePromptGrid(
                            selectedPromptId: enhancementService.selectedPromptId,
                            onPromptSelected: { prompt in
                                enhancementService.setActivePrompt(prompt)
                            },
                            onEditPrompt: { prompt in
                                selectedPromptForEdit = prompt
                            },
                            onDeletePrompt: { prompt in
                                enhancementService.deletePrompt(prompt)
                            },
                            onAddNewPrompt: {
                                isEditingPrompt = true
                            }
                        )
                    }
                    .padding(VoiceInkSpacing.lg)
                    .voiceInkCardBackground()
                    
                    EnhancementShortcutsSection()
                }
            }
            .padding(VoiceInkSpacing.lg)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(VoiceInkTheme.Palette.canvas)
        .sheet(isPresented: $isEditingPrompt) {
            PromptEditorView(mode: .add)
        }
        .sheet(item: $selectedPromptForEdit) { prompt in
            PromptEditorView(mode: .edit(prompt))
        }
    }
}

// MARK: - Drag & Drop Reorderable Grid
private struct ReorderablePromptGrid: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    
    let selectedPromptId: UUID?
    let onPromptSelected: (CustomPrompt) -> Void
    let onEditPrompt: ((CustomPrompt) -> Void)?
    let onDeletePrompt: ((CustomPrompt) -> Void)?
    let onAddNewPrompt: (() -> Void)?
    
    @State private var draggingItem: CustomPrompt?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if enhancementService.customPrompts.isEmpty {
                Text("No prompts available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 36)
                ]
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(enhancementService.customPrompts) { prompt in
                        prompt.promptIcon(
                            isSelected: selectedPromptId == prompt.id,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    onPromptSelected(prompt)
                                }
                            },
                            onEdit: onEditPrompt,
                            onDelete: onDeletePrompt
                        )
                        .opacity(draggingItem?.id == prompt.id ? 0.3 : 1.0)
                        .scaleEffect(draggingItem?.id == prompt.id ? 1.05 : 1.0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    draggingItem != nil && draggingItem?.id != prompt.id
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .animation(.easeInOut(duration: 0.15), value: draggingItem?.id == prompt.id)
                        .onDrag {
                            draggingItem = prompt
                            return NSItemProvider(object: prompt.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PromptDropDelegate(
                                item: prompt,
                                prompts: $enhancementService.customPrompts,
                                draggingItem: $draggingItem
                            )
                        )
                    }
                    
                    if let onAddNewPrompt = onAddNewPrompt {
                        CustomPrompt.addNewButton {
                            onAddNewPrompt()
                        }
                        .help("Add new prompt")
                        .onDrop(
                            of: [UTType.text],
                            delegate: PromptEndDropDelegate(
                                prompts: $enhancementService.customPrompts,
                                draggingItem: $draggingItem
                            )
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Double-click to edit • Right-click for more options")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Drop Delegates
private struct PromptDropDelegate: DropDelegate {
    let item: CustomPrompt
    @Binding var prompts: [CustomPrompt]
    @Binding var draggingItem: CustomPrompt?
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem, draggingItem != item else { return }
        guard let fromIndex = prompts.firstIndex(of: draggingItem),
              let toIndex = prompts.firstIndex(of: item) else { return }
        
        // Move item as you hover for immediate visual update
        if prompts[toIndex].id != draggingItem.id {
            withAnimation(.easeInOut(duration: 0.12)) {
                let from = fromIndex
                let to = toIndex
                prompts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}

private struct PromptEndDropDelegate: DropDelegate {
    @Binding var prompts: [CustomPrompt]
    @Binding var draggingItem: CustomPrompt?
    
    func validateDrop(info: DropInfo) -> Bool { true }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggingItem = draggingItem,
              let currentIndex = prompts.firstIndex(of: draggingItem) else {
            self.draggingItem = nil
            return false
        }
        
        // Move to end if dropped on the trailing "Add New" tile
        withAnimation(.easeInOut(duration: 0.12)) {
            prompts.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: prompts.endIndex)
        }
        self.draggingItem = nil
        return true
    }
}
