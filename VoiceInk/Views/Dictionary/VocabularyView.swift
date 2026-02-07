import SwiftUI
import SwiftData

enum VocabularySortMode: String {
    case wordAsc = "wordAsc"
    case wordDesc = "wordDesc"
}

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularyWords: [VocabularyWord]

    @ObservedObject var whisperPrompt: WhisperPrompt
    @State private var newWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var sortMode: VocabularySortMode = .wordAsc

    init(whisperPrompt: WhisperPrompt) {
        self.whisperPrompt = whisperPrompt

        if let savedSort = AppSettings.Dictionary.dictionarySortMode,
           let mode = VocabularySortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedItems: [VocabularyWord] {
        switch sortMode {
        case .wordAsc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .wordDesc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedDescending }
        }
    }

    private var shouldShowAddButton: Bool {
        !newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                Label {
                    Text("Add words to help \(AppBrand.communityName) recognize them properly. (Requires AI enhancement)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                }
            }

            HStack(spacing: 8) {
                TextField("Add word to vocabulary", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addWords() }

                if shouldShowAddButton {
                    Button(action: addWords) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(newWord.isEmpty)
                    .help("Add word")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if !vocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: toggleSort) {
                        HStack(spacing: 4) {
                            Text("Vocabulary Words (\(vocabularyWords.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            Image(systemName: sortMode == .wordAsc ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Sort alphabetically")

                    ScrollView {
                        FlowLayout(spacing: 8) {
                            ForEach(sortedItems) { item in
                                VocabularyWordView(item: item) {
                                    removeWord(item)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .alert("Vocabulary", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .task {
            importPersistedVocabularyIfNeeded()
            persistVocabularySnapshot()
        }
    }

    private func toggleSort() {
        sortMode = (sortMode == .wordAsc) ? .wordDesc : .wordAsc
        AppSettings.Dictionary.dictionarySortMode = sortMode.rawValue
    }

    private func addWords() {
        let input = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let parts = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return }

        if parts.count == 1, let word = parts.first {
            if vocabularyWords.contains(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) {
                alertMessage = "'\(word)' is already in the vocabulary"
                showAlert = true
                return
            }
            addWord(word)
            newWord = ""
            return
        }

        for word in parts {
            let alreadyExists = vocabularyWords.contains(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame })
            if !alreadyExists {
                addWord(word)
            }
        }
        newWord = ""
    }

    private func addWord(_ word: String) {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWord.isEmpty else { return }
        guard !vocabularyWords.contains(where: { $0.word.caseInsensitiveCompare(normalizedWord) == .orderedSame }) else { return }

        let newVocabularyWord = VocabularyWord(word: normalizedWord)
        modelContext.insert(newVocabularyWord)

        do {
            try modelContext.save()
            persistVocabularySnapshot()
        } catch {
            modelContext.delete(newVocabularyWord)
            alertMessage = "Failed to add word: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func removeWord(_ word: VocabularyWord) {
        modelContext.delete(word)

        do {
            try modelContext.save()
            persistVocabularySnapshot()
        } catch {
            modelContext.rollback()
            alertMessage = "Failed to remove word: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func importPersistedVocabularyIfNeeded() {
        guard vocabularyWords.isEmpty,
              let data = AppSettings.Dictionary.customVocabularyItemsData,
              let persistedWords = try? JSONDecoder().decode([VocabularyWordData].self, from: data),
              !persistedWords.isEmpty else {
            return
        }

        var seen = Set<String>()
        for entry in persistedWords {
            let trimmed = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            modelContext.insert(VocabularyWord(word: trimmed, dateAdded: entry.dateAdded ?? Date()))
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }

    private func persistVocabularySnapshot() {
        let payload = vocabularyWords.map { item in
            VocabularyWordData(word: item.word, dateAdded: item.dateAdded)
        }
        if let encoded = try? JSONEncoder().encode(payload) {
            AppSettings.Dictionary.customVocabularyItemsData = encoded
        }
    }
}

struct VocabularyWordView: View {
    let item: VocabularyWord
    let onDelete: () -> Void
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(item.word)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(.primary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDeleteHovered ? .red : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Remove word")
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDeleteHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor).opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}
