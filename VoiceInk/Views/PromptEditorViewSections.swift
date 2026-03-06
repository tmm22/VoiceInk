import SwiftUI

struct PromptIconSelector: View {
    @Binding var selectedIcon: PromptIcon
    @Binding var showingPicker: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: { showingPicker = true }) {
                Image(systemName: selectedIcon)
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                    .frame(width: 56, height: 56)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            IconPickerPopover(selectedIcon: $selectedIcon, isPresented: $showingPicker)
        }
    }
}

struct PromptEditorDescriptionSection: View {
    @Binding var description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Add a brief description of what this prompt does")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Enter a description", text: $description)
                .textFieldStyle(.roundedBorder)
                .font(.body)
        }
    }
}

struct PromptPersonaSummary: View {
    let userBio: String

    var body: some View {
        if !userBio.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Persona:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text(userBio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)
            .padding(.bottom, 4)
        }
    }
}

struct PromptEditorHeaderFields: View {
    @Binding var title: String
    @Binding var useSystemInstructions: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Use System Instructions", isOn: $useSystemInstructions)

            TextField("Prompt Name", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        .background(Color(NSColor.controlBackgroundColor).cornerRadius(6))
                )
        }
    }
}

struct PromptEditorCompactDescriptionField: View {
    @Binding var description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Brief description of what this prompt does", text: $description)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        .background(Color(NSColor.controlBackgroundColor).cornerRadius(6))
                )
        }
    }
}

struct PromptInstructionsTextEditor: View {
    @Binding var promptText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions")
                .font(.headline)
                .foregroundColor(.primary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $promptText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                if promptText.isEmpty {
                    Text("Enter your custom prompt instructions here...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct PromptSystemTemplateToggle: View {
    @Binding var useSystemInstructions: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Use System Template", isOn: $useSystemInstructions)
                .toggleStyle(.switch)
                .controlSize(.small)

            InfoTip("If enabled, your instructions are combined with a general-purpose template to improve transcription quality.\n\nDisable for full control over the AI's system prompt (for advanced users).")
        }
    }
}

struct PromptTemplateMenu: View {
    let onTemplateSelected: (TemplatePrompt) -> Void

    var body: some View {
        HStack {
            Menu {
                ForEach(PromptTemplates.all, id: \.title) { template in
                    Button {
                        onTemplateSelected(template)
                    } label: {
                        HStack {
                            Text(template.title)
                            Spacer()
                            Image(systemName: template.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                    Text("Start with Template")
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
    }
}
