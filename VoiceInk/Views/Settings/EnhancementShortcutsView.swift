import SwiftUI
import KeyboardShortcuts

struct EnhancementShortcutsView: View {
    @ObservedObject private var shortcutSettings = EnhancementShortcutSettings.shared

    var body: some View {
        VStack(spacing: 12) {
            EnhancementShortcutRow(
                title: "Toggle AI Enhancement",
                description: "Quickly enable or disable enhancement while recording.",
                keyDisplay: ["⌘", "E"],
                isOn: $shortcutSettings.isToggleEnhancementShortcutEnabled
            )
            EnhancementShortcutRow(
                title: "Switch Enhancement Prompt",
                description: "Switch between your saved prompts without touching the UI. Use ⌘1–⌘0 to activate the corresponding prompt in the order they are saved.",
                keyDisplay: ["⌘", "1 – 0"]
            )
        }
        .background(Color.clear)
    }
}

// MARK: - Supporting Views
private struct EnhancementShortcutRow: View {
    let title: String
    let description: String
    let keyDisplay: [String]
    private var isOn: Binding<Bool>?

    init(title: String, description: String, keyDisplay: [String], isOn: Binding<Bool>? = nil) {
        self.title = title
        self.description = description
        self.keyDisplay = keyDisplay
        self.isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    InfoTip(title: title, message: description, learnMoreURL: "https://tryvoiceink.com/docs/switching-enhancement-prompts")
                }

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if let isOn = isOn {
                keyDisplayView(isActive: isOn.wrappedValue)
                    .onTapGesture {
                        withAnimation(.bouncy) {
                            isOn.wrappedValue.toggle()
                        }
                    }
                    .contentShape(Rectangle())
            } else {
                keyDisplayView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(CardBackground(isSelected: false))
    }

    @ViewBuilder
    private func keyDisplayView(isActive: Bool? = nil) -> some View {
        HStack(spacing: 8) {
            ForEach(keyDisplay, id: \.self) { key in
                KeyChip(label: key, isActive: isActive)
            }
        }
    }
}

private struct KeyChip: View {
    let label: String
    var isActive: Bool? = nil

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(isActive == false ? .secondary : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        isActive == true
                            ? Color.accentColor.opacity(0.18)
                            : Color(NSColor.controlBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        Color(NSColor.separatorColor).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
    }
}
