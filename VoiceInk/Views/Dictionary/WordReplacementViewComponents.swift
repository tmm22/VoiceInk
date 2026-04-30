import SwiftUI

struct WordReplacementInputRow: View {
    @Binding var originalWord: String
    @Binding var replacementWord: String
    let showsAddButton: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Original text (use commas for multiple)", text: $originalWord)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            TextField("Replacement text", text: $replacementWord)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit { onAdd() }

            if showsAddButton {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add word replacement")
                .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                .help("Add word replacement")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsAddButton)
    }
}

struct WordReplacementListSection: View {
    let replacements: [WordReplacement]
    let sortMode: WordReplacementSortMode
    let onToggleSort: (WordReplacementSortColumn) -> Void
    let onDelete: (WordReplacement) -> Void
    let onEdit: (WordReplacement) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                sortButton(
                    title: "Original",
                    systemImage: sortMode == .originalAsc ? "chevron.up" : "chevron.down",
                    isActive: sortMode == .originalAsc || sortMode == .originalDesc
                ) {
                    onToggleSort(.original)
                }

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                    .frame(width: 10)

                sortButton(
                    title: "Replacement",
                    systemImage: sortMode == .replacementAsc ? "chevron.up" : "chevron.down",
                    isActive: sortMode == .replacementAsc || sortMode == .replacementDesc
                ) {
                    onToggleSort(.replacement)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(replacements) { replacement in
                        ReplacementRow(
                            original: replacement.originalText,
                            replacement: replacement.replacementText,
                            onDelete: { onDelete(replacement) },
                            onEdit: { onEdit(replacement) }
                        )

                        if replacement.id != replacements.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(.top, 4)
    }

    private func sortButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                if isActive {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Sort by \(title.lowercased())")
    }
}

struct ReplacementRow: View {
    let original: String
    let replacement: String
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var isEditHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(original)
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            ZStack(alignment: .trailing) {
                Text(replacement)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 50)

                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(isEditHovered ? .accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit replacement from \(original) to \(replacement)")
                    .help("Edit replacement")
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditHovered = hover
                        }
                    }

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isDeleteHovered ? .red : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove replacement from \(original) to \(replacement)")
                    .help("Remove replacement")
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDeleteHovered = hover
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(original), replaced with \(replacement)")
    }
}
