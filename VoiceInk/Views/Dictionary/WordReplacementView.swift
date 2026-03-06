import SwiftUI
import SwiftData

struct WordReplacementView: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @State private var showAlert = false
    @State private var editingReplacement: WordReplacement?
    @State private var alertMessage = ""
    @State private var sortMode: WordReplacementSortMode = .originalAsc
    @State private var originalWord = ""
    @State private var replacementWord = ""
    @State private var showInfoPopover = false

    init() {
        if let savedSort = AppSettings.Dictionary.wordReplacementSortMode,
           let mode = WordReplacementSortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedReplacements: [WordReplacement] {
        switch sortMode {
        case .originalAsc:
            return wordReplacements.sorted {
                $0.originalText.localizedCaseInsensitiveCompare($1.originalText) == .orderedAscending
            }
        case .originalDesc:
            return wordReplacements.sorted {
                $0.originalText.localizedCaseInsensitiveCompare($1.originalText) == .orderedDescending
            }
        case .replacementAsc:
            return wordReplacements.sorted {
                $0.replacementText.localizedCaseInsensitiveCompare($1.replacementText) == .orderedAscending
            }
        case .replacementDesc:
            return wordReplacements.sorted {
                $0.replacementText.localizedCaseInsensitiveCompare($1.replacementText) == .orderedDescending
            }
        }
    }

    private var shouldShowAddButton: Bool {
        !originalWord.isEmpty || !replacementWord.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                Label {
                    Text("Define word replacements to automatically replace specific words or phrases")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Button(action: { showInfoPopover.toggle() }) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfoPopover) {
                        WordReplacementInfoPopover()
                    }
                }
            }

            WordReplacementInputRow(
                originalWord: $originalWord,
                replacementWord: $replacementWord,
                showsAddButton: shouldShowAddButton,
                onAdd: addReplacement
            )

            if !wordReplacements.isEmpty {
                WordReplacementListSection(
                    replacements: sortedReplacements,
                    sortMode: sortMode,
                    onToggleSort: toggleSort,
                    onDelete: removeReplacement,
                    onEdit: { editingReplacement = $0 }
                )
            }
        }
        .padding()
        .sheet(item: $editingReplacement) { replacement in
            EditReplacementSheet(replacement: replacement, modelContext: modelContext)
        }
        .alert("Word Replacement", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func toggleSort(for column: WordReplacementSortColumn) {
        switch column {
        case .original:
            sortMode = (sortMode == .originalAsc) ? .originalDesc : .originalAsc
        case .replacement:
            sortMode = (sortMode == .replacementAsc) ? .replacementDesc : .replacementAsc
        }
        AppSettings.Dictionary.wordReplacementSortMode = sortMode.rawValue
    }

    private func addReplacement() {
        let original = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)

        let tokens = original
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty && !replacement.isEmpty else { return }

        let newTokens = Set(tokens.map { $0.lowercased() })

        for existingReplacement in wordReplacements {
            let existingTokens = existingReplacement.originalText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }

            if let duplicate = existingTokens.first(where: { newTokens.contains($0) }) {
                alertMessage = "'\(duplicate)' already exists in word replacements"
                showAlert = true
                return
            }
        }

        let newReplacement = WordReplacement(originalText: original, replacementText: replacement)
        modelContext.insert(newReplacement)

        do {
            try modelContext.save()
            originalWord = ""
            replacementWord = ""
        } catch {
            modelContext.delete(newReplacement)
            alertMessage = "Failed to add replacement: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func removeReplacement(_ replacement: WordReplacement) {
        modelContext.delete(replacement)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            alertMessage = "Failed to remove replacement: \(error.localizedDescription)"
            showAlert = true
        }
    }
}
