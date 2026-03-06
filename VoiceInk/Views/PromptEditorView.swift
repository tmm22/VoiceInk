import SwiftUI

struct PromptEditorView: View {
    enum Mode {
        case add
        case edit(CustomPrompt)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.add, .add):
                return true
            case let (.edit(prompt1), .edit(prompt2)):
                return prompt1.id == prompt2.id
            default:
                return false
            }
        }
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var enhancementService: AIEnhancementService
    var onDismiss: (() -> Void)?
    @State private var title: String
    @State private var promptText: String
    @State private var selectedIcon: PromptIcon
    @State private var description: String
    @State private var triggerWords: [String]
    @State private var useSystemInstructions: Bool
    @State private var showingIconPicker = false

    private var isEditingPredefinedPrompt: Bool {
        if case .edit(let prompt) = mode {
            return prompt.isPredefined
        }
        return false
    }

    init(mode: Mode, onDismiss: (() -> Void)? = nil) {
        self.mode = mode
        self.onDismiss = onDismiss

        switch mode {
        case .add:
            _title = State(initialValue: "")
            _promptText = State(initialValue: "")
            _selectedIcon = State(initialValue: "doc.text.fill")
            _description = State(initialValue: "")
            _triggerWords = State(initialValue: [])
            _useSystemInstructions = State(initialValue: true)
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _promptText = State(initialValue: prompt.promptText)
            _selectedIcon = State(initialValue: prompt.icon)
            _description = State(initialValue: prompt.description ?? "")
            _triggerWords = State(initialValue: prompt.triggerWords)
            _useSystemInstructions = State(initialValue: prompt.useSystemInstructions)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 24) {
                    if isEditingPredefinedPrompt {
                        predefinedPromptEditor
                    } else {
                        customPromptEditor
                    }
                }
            }

            footer
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(isEditingPredefinedPrompt ? "Edit Trigger Words" : (mode == .add ? "New Prompt" : "Edit Prompt"))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private var predefinedPromptEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Editing: \(title)")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Text("You can only customize the trigger words for system prompts.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TriggerWordsEditor(triggerWords: $triggerWords)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var customPromptEditor: some View {
        VStack(spacing: 24) {
            PromptIconSelector(
                selectedIcon: $selectedIcon,
                showingPicker: $showingIconPicker
            )

            PromptEditorDescriptionSection(description: $description)
                .padding(.horizontal)

            promptInstructionsSection
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
        }
    }

    private var promptInstructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt Instructions")
                .font(.headline)
                .foregroundColor(.secondary)

            PromptPersonaSummary(userBio: enhancementService.contextSettings.userBio)

            Text("Define how AI should enhance your transcriptions")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !isEditingPredefinedPrompt {
                PromptEditorHeaderFields(
                    title: $title,
                    useSystemInstructions: $useSystemInstructions
                )
            }

            PromptEditorCompactDescriptionField(description: $description)

            Divider().padding(.vertical, 4)

            PromptInstructionsTextEditor(promptText: $promptText)

            if !isEditingPredefinedPrompt {
                PromptSystemTemplateToggle(useSystemInstructions: $useSystemInstructions)
                    .padding(.top, 4)
            }

            Divider().padding(.vertical, 4)

            TriggerWordsEditor(triggerWords: $triggerWords)

            if case .add = mode, !isEditingPredefinedPrompt {
                PromptTemplateMenu(
                    onTemplateSelected: { template in
                        title = template.title
                        promptText = template.promptText
                        selectedIcon = template.icon
                        description = template.description
                    }
                )
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Button("Cancel") {
                    close()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Button {
                    save()
                    close()
                } label: {
                    Text("Save Changes")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEditingPredefinedPrompt ? false : (title.isEmpty || promptText.isEmpty))
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func save() {
        switch mode {
        case .add:
            enhancementService.addPrompt(
                title: title,
                promptText: promptText,
                icon: selectedIcon,
                description: description.isEmpty ? nil : description,
                triggerWords: triggerWords,
                useSystemInstructions: useSystemInstructions
            )
        case .edit(let prompt):
            let updatedPrompt = CustomPrompt(
                id: prompt.id,
                title: prompt.isPredefined ? prompt.title : title,
                promptText: prompt.isPredefined ? prompt.promptText : promptText,
                isActive: prompt.isActive,
                icon: prompt.isPredefined ? prompt.icon : selectedIcon,
                description: prompt.isPredefined ? prompt.description : (description.isEmpty ? nil : description),
                isPredefined: prompt.isPredefined,
                triggerWords: triggerWords,
                useSystemInstructions: useSystemInstructions
            )
            enhancementService.updatePrompt(updatedPrompt)
        }
    }
}
