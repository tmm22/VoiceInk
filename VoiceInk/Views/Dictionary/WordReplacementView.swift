import SwiftUI
import SwiftData

extension String: @retroactive Identifiable {
    public var id: String { self }
}

enum SortMode: String {
    case originalAsc = "originalAsc"
    case originalDesc = "originalDesc"
    case replacementAsc = "replacementAsc"
    case replacementDesc = "replacementDesc"
}

enum SortColumn {
    case original
    case replacement
}

@MainActor
class WordReplacementManager: ObservableObject {
    @Published var replacements: [String: String] {
        didSet {
            AppSettings.Dictionary.wordReplacements = replacements
        }
    }

    init() {
        self.replacements = AppSettings.Dictionary.wordReplacements
    }
    
    func addReplacement(original: String, replacement: String) {
        // Preserve comma-separated originals as a single entry
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replacements[trimmed] = replacement
    }
    
    func removeReplacement(original: String) {
        replacements.removeValue(forKey: original)
    }
    
    func updateReplacement(oldOriginal: String, newOriginal: String, newReplacement: String) {
        // Replace old key with the new comma-preserved key
        replacements.removeValue(forKey: oldOriginal)
        let trimmed = newOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replacements[trimmed] = newReplacement
    }
}

struct WordReplacementView: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @State private var showAlert = false
    @State private var editingReplacement: WordReplacement? = nil
    @State private var alertMessage = ""
    @State private var sortMode: SortMode = .originalAsc
    @State private var originalWord = ""
    @State private var replacementWord = ""
    @State private var showInfoPopover = false

    init() {
        if let savedSort = AppSettings.Dictionary.wordReplacementSortMode,
           let mode = SortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedReplacements: [WordReplacement] {
        switch sortMode {
        case .originalAsc:
            return wordReplacements.sorted { $0.originalText.localizedCaseInsensitiveCompare($1.originalText) == .orderedAscending }
        case .originalDesc:
            return wordReplacements.sorted { $0.originalText.localizedCaseInsensitiveCompare($1.originalText) == .orderedDescending }
        case .replacementAsc:
            return wordReplacements.sorted { $0.replacementText.localizedCaseInsensitiveCompare($1.replacementText) == .orderedAscending }
        case .replacementDesc:
            return wordReplacements.sorted { $0.replacementText.localizedCaseInsensitiveCompare($1.replacementText) == .orderedDescending }
        }
    }
    
    private func toggleSort(for column: SortColumn) {
        switch column {
        case .original:
            sortMode = (sortMode == .originalAsc) ? .originalDesc : .originalAsc
        case .replacement:
            sortMode = (sortMode == .replacementAsc) ? .replacementDesc : .replacementAsc
        }
        AppSettings.Dictionary.wordReplacementSortMode = sortMode.rawValue
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
                    .onSubmit { addReplacement() }

                if shouldShowAddButton {
                    Button(action: addReplacement) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                    .help("Add word replacement")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if !wordReplacements.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button(action: { toggleSort(for: .original) }) {
                            HStack(spacing: 4) {
                                Text("Original")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                if sortMode == .originalAsc || sortMode == .originalDesc {
                                    Image(systemName: sortMode == .originalAsc ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Sort by original")

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                            .frame(width: 10)

                        Button(action: { toggleSort(for: .replacement) }) {
                            HStack(spacing: 4) {
                                Text("Replacement")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                if sortMode == .replacementAsc || sortMode == .replacementDesc {
                                    Image(systemName: sortMode == .replacementAsc ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Sort by replacement")
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedReplacements) { replacement in
                                ReplacementRow(
                                    original: replacement.originalText,
                                    replacement: replacement.replacementText,
                                    onDelete: { removeReplacement(replacement) },
                                    onEdit: { editingReplacement = replacement }
                                )

                                if replacement.id != sortedReplacements.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding(.top, 4)
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
            // Roll back the optimistic insert if persistence fails.
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

struct EmptyStateView: View {
    @Binding var showAddModal: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.word.spacing")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("No Replacements")
                .font(.headline)
            
            Text("Add word replacements to automatically replace text.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
            
            Button("Add Replacement") {
                showAddModal = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AddReplacementSheet: View {
    @ObservedObject var manager: WordReplacementManager
    @Environment(\.dismiss) private var dismiss
    @State private var originalWord = ""
    @State private var replacementWord = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Text("Add Word Replacement")
                    .font(.headline)
                
                Spacer()
                
                Button("Add") {
                    addReplacement()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(CardBackground(isSelected: false))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Description
                    Text("Define a word or phrase to be automatically replaced.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Form Content
                    VStack(spacing: 16) {
                        // Original Text Section
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Original Text")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            TextField("Enter word or phrase to replace (use commas for multiple)", text: $originalWord)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                            Text("Separate multiple originals with commas, e.g. Voicing, Voice ink, Voiceing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        // Replacement Text Section
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Replacement Text")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            TextEditor(text: $replacementWord)
                                .font(.body)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(.textBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(.separatorColor), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Example Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Examples")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Single original -> replacement
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Original:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("my website link")
                                    .font(.callout)
                            }
                            
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Replacement:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("https://tryvoiceink.com")
                                    .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)

                        // Comma-separated originals -> single replacement
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Original:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Voicing, Voice ink, Voiceing")
                                    .font(.callout)
                            }
                            
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Replacement:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(AppBrand.communityName)")
                                    .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.vertical)
            }
        }
        .frame(width: 460, height: 520)
    }
    
    private func addReplacement() {
        let original = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !replacement.isEmpty else { return }

        manager.addReplacement(original: original, replacement: replacement)
        dismiss()
    }
}

struct WordReplacementInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to use Word Replacements")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Separate multiple originals with commas:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Voicing, Voice ink, Voiceing")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            Text("Examples")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("my website link")
                            .font(.callout)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replacement:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("https://tryvoiceink.com")
                            .font(.callout)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Voicing, Voice ink")
                            .font(.callout)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replacement:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("VoiceInk")
                            .font(.callout)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding()
        .frame(width: 380)
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
    }
} 
