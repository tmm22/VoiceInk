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
                        
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Clipboard Context", isOn: $enhancementService.useClipboardContext)
                                    .toggleStyle(.switch)
                                    .disabled(!enhancementService.isEnhancementEnabled)
                                Text("Use text from clipboard to understand the context")
                                    .voiceInkCaptionStyle()
                                    .foregroundColor(enhancementService.isEnhancementEnabled ? .secondary : .secondary.opacity(0.5))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Context Awareness", isOn: $enhancementService.useScreenCaptureContext)
                                    .toggleStyle(.switch)
                                    .disabled(!enhancementService.isEnhancementEnabled)
                                Text("Learn what is on the screen to understand the context")
                                    .voiceInkCaptionStyle()
                                    .foregroundColor(enhancementService.isEnhancementEnabled ? .secondary : .secondary.opacity(0.5))
                            }
                        }
                    }
                    .padding(VoiceInkSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .fill(VoiceInkTheme.Card.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                    .stroke(VoiceInkTheme.Card.stroke, lineWidth: 1)
                            )
                    )
                    
                    if enableAIEnhancementFeatures {
                        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                            Text("AI Provider Integration")
                                .voiceInkHeadline()
                            
                            APIKeyManagementView()
                            
                            Divider()
                                .padding(.vertical, VoiceInkSpacing.sm)
                            
                            // Request Timeout Setting
                            VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                                HStack {
                                    Text("Request Timeout")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    InfoTip(
                                        title: "Request Timeout",
                                        message: "Maximum time to wait for AI enhancement responses. Increase this value for slower connections, complex prompts, or when using models that require more processing time."
                                    )
                                    
                                    Spacer()
                                }
                                
                                HStack(spacing: VoiceInkSpacing.md) {
                                    Slider(
                                        value: $enhancementService.requestTimeout,
                                        in: AIEnhancementService.minimumTimeout...AIEnhancementService.maximumTimeout,
                                        step: 5
                                    )
                                    .frame(maxWidth: .infinity)
                                    
                                    Text(formatTimeout(enhancementService.requestTimeout))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .trailing)
                                }
                                
                                Text("Default: 30 seconds")
                                    .voiceInkCaptionStyle()
                            }
                        }
                        .padding(VoiceInkSpacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                .fill(VoiceInkTheme.Card.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                        .stroke(VoiceInkTheme.Card.stroke, lineWidth: 1)
                                )
                        )
                    } else {
                        VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                            Label("Local-Only Enhancement", systemImage: "lock.shield")
                                .font(.headline)
                            
                            Text("The community build keeps enhancement providers on-device by default. Enable AI enhancements in Settings to configure cloud providers like OpenAI or Google.")
                                .voiceInkCaptionStyle()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(VoiceInkSpacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                .fill(VoiceInkTheme.Card.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                        .stroke(VoiceInkTheme.Card.stroke, lineWidth: 1)
                                )
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                        Text("Enhancement Prompt")
                            .voiceInkHeadline()
                        
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
                    .background(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .fill(VoiceInkTheme.Card.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                        .stroke(VoiceInkTheme.Card.stroke, lineWidth: 1)
                            )
                    )
                    
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
