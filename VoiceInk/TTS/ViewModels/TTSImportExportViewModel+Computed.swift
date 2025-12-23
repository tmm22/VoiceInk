import Foundation

extension TTSImportExportViewModel {
    var canSummarizeImports: Bool {
        summarizationService.hasCredentials()
    }

    var articleSummaryPreview: String? {
        articleSummary?.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var condensedImportPreview: String? {
        articleSummary?.condensedText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var articleSummaryReductionDescription: String? {
        guard let summary = articleSummary,
              let condensedCount = summary.condensedWordCount,
              summary.originalWordCount > 0 else {
            return articleSummary?.wordSavingsDescription
        }

        let reduction = 1 - (Double(condensedCount) / Double(summary.originalWordCount))
        guard reduction > 0 else { return articleSummary?.wordSavingsDescription }
        let percent = Int((reduction * 100).rounded())
        return percent > 0 ? "Cuts roughly \(percent)% of the article before narration." : articleSummary?.wordSavingsDescription
    }

    var canAdoptCondensedImport: Bool {
        guard let text = condensedImportPreview else { return false }
        return !text.isEmpty
    }

    var canInsertSummaryIntoEditor: Bool {
        guard let summary = articleSummaryPreview else { return false }
        return !summary.isEmpty
    }

    var canSpeakSummary: Bool {
        canInsertSummaryIntoEditor
    }
}
