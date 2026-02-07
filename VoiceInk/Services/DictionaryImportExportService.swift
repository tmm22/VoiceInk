import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftData

struct DictionaryExportData: Codable {
    let version: String
    let vocabularyWords: [String]
    let wordReplacements: [String: String]
    let exportDate: Date
}

class DictionaryImportExportService {
    static let shared = DictionaryImportExportService()

    private init() {}

    func exportDictionary(from context: ModelContext) {
        _ = context
        let dictionaryWords = loadVocabularyWords()
        let wordReplacements = AppSettings.Dictionary.wordReplacements

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let exportData = DictionaryExportData(
            version: version,
            vocabularyWords: dictionaryWords,
            wordReplacements: wordReplacements,
            exportDate: Date()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        do {
            let jsonData = try encoder.encode(exportData)

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.nameFieldStringValue = "VoiceInk_Dictionary.json"
            savePanel.title = "Export Dictionary Data"
            savePanel.message = "Choose a location to save your vocabulary and word replacements."

            Task { @MainActor in
                if savePanel.runModal() == .OK, let url = savePanel.url {
                    do {
                        try jsonData.write(to: url)
                        self.showAlert(title: "Export Successful", message: "Dictionary data exported successfully to \(url.lastPathComponent).")
                    } catch {
                        self.showAlert(title: "Export Error", message: "Could not save dictionary data: \(error.localizedDescription)")
                    }
                } else {
                    self.showAlert(title: "Export Canceled", message: "Export operation was canceled.")
                }
            }
        } catch {
            showAlert(title: "Export Error", message: "Could not encode dictionary data: \(error.localizedDescription)")
        }
    }

    func importDictionary(into context: ModelContext) {
        _ = context

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import Dictionary Data"
        openPanel.message = "Choose a dictionary file to import. New items will be added, existing items will be kept."

        Task { @MainActor in
            if openPanel.runModal() == .OK, let url = openPanel.url {
                do {
                    let jsonData = try await FileDataLoader.loadData(from: url)
                    let importedData = try await Task.detached(priority: .utility) {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        return try decoder.decode(DictionaryExportData.self, from: jsonData)
                    }.value

                    var existingWords = loadVocabularyWords()
                    var existingWordsLower = Set(existingWords.map { $0.lowercased() })
                    let originalExistingCount = existingWords.count
                    var newWordsAdded = 0

                    for importedWord in importedData.vocabularyWords {
                        let normalized = importedWord.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !normalized.isEmpty else { continue }
                        if !existingWordsLower.contains(normalized.lowercased()) {
                            existingWords.append(normalized)
                            existingWordsLower.insert(normalized.lowercased())
                            newWordsAdded += 1
                        }
                    }

                    saveVocabularyWords(existingWords)

                    var existingReplacements = AppSettings.Dictionary.wordReplacements
                    var addedCount = 0
                    var updatedCount = 0

                    for (importedKey, importedReplacement) in importedData.wordReplacements {
                        let normalizedImportedKey = normalizeReplacementKey(importedKey)
                        let importedWords = extractWords(from: normalizedImportedKey)

                        var modifiedExisting: [String: String] = [:]
                        for (existingKey, existingReplacement) in existingReplacements {
                            var existingWords = extractWords(from: existingKey)
                            var modified = false

                            for importedWord in importedWords {
                                if let index = existingWords.firstIndex(where: { $0.lowercased() == importedWord.lowercased() }) {
                                    existingWords.remove(at: index)
                                    modified = true
                                }
                            }

                            if !existingWords.isEmpty {
                                let newKey = existingWords.joined(separator: ", ")
                                modifiedExisting[newKey] = existingReplacement
                            }

                            if modified {
                                updatedCount += 1
                            }
                        }

                        existingReplacements = modifiedExisting
                        existingReplacements[normalizedImportedKey] = importedReplacement
                        addedCount += 1
                    }

                    AppSettings.Dictionary.wordReplacements = existingReplacements

                    var message = "Dictionary data imported successfully from \(url.lastPathComponent).\n\n"
                    message += "Vocabulary: \(newWordsAdded) added, \(originalExistingCount) kept\n"
                    message += "Word Replacements: \(addedCount) added, \(updatedCount) updated"

                    showAlert(title: "Import Successful", message: message)
                } catch {
                    showAlert(title: "Import Error", message: "Error importing dictionary data: \(error.localizedDescription). The file might be corrupted or not in the correct format.")
                }
            } else {
                showAlert(title: "Import Canceled", message: "Import operation was canceled.")
            }
        }
    }

    private func loadVocabularyWords() -> [String] {
        guard let data = AppSettings.Dictionary.customVocabularyItemsData,
              let items = try? JSONDecoder().decode([VocabularyWordData].self, from: data) else {
            return []
        }

        return items
            .map { $0.word.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func saveVocabularyWords(_ words: [String]) {
        let payload = words.map { VocabularyWordData(word: $0) }
        if let encoded = try? JSONEncoder().encode(payload) {
            AppSettings.Dictionary.customVocabularyItemsData = encoded
        }
    }

    private func normalizeReplacementKey(_ key: String) -> String {
        let words = extractWords(from: key)
        return words.joined(separator: ", ")
    }

    private func extractWords(from key: String) -> [String] {
        key
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func showAlert(title: String, message: String) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
