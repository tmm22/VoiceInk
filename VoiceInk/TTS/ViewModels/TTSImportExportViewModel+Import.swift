import Foundation

extension TTSImportExportViewModel {
    func clearArticleSummary() {
        articleSummaryTask?.cancel()
        articleSummaryTask = nil
        articleSummary = nil
        articleSummaryError = nil
        isSummarizingArticle = false
    }

    func importText(from urlString: String, autoGenerate: Bool) async {
        guard let coordinator else { return }

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            coordinator.errorMessage = "Enter a URL to import content."
            return
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            coordinator.errorMessage = "URL must start with http:// or https://."
            return
        }

        isImportingFromURL = true
        coordinator.errorMessage = nil
        defer { isImportingFromURL = false }

        do {
            let rawText = try await urlContentLoader.fetchPlainText(from: url)
            let normalized = normalizeImportedText(rawText)

            guard !normalized.isEmpty else {
                coordinator.errorMessage = "Unable to find readable text at that address."
                articleSummary = nil
                return
            }

            let limit = settings.characterLimit(for: settings.selectedProvider)
            let formattedLimit = settings.formattedCharacterLimit(for: settings.selectedProvider)
            let segments = TextChunker.chunk(text: normalized, limit: limit)

            guard let firstSegment = segments.first else {
                coordinator.errorMessage = "Unable to find readable text at that address."
                articleSummary = nil
                return
            }

            let preparedText: String
            if segments.count > 1 {
                let separator = "\n\n\(batchDelimiterToken)\n\n"
                preparedText = segments.joined(separator: separator)
                coordinator.errorMessage = nil
            } else if firstSegment.count > limit {
                preparedText = String(firstSegment.prefix(limit))
                coordinator.errorMessage = "Imported text exceeded \(formattedLimit) characters. The content was truncated."
            } else {
                preparedText = firstSegment
                coordinator.errorMessage = nil
            }

            coordinator.inputText = preparedText

            articleSummaryTask?.cancel()
            articleSummary = ArticleImportSummary.make(sourceURL: url, originalText: normalized)
            articleSummaryError = nil

            if canSummarizeImports {
                let summarySource = normalized
                articleSummaryTask = Task { [weak self] in
                    guard let self else { return }
                    await self.generateArticleSummary(for: summarySource, url: url)
                    self.articleSummaryTask = nil
                }
            } else {
                articleSummaryError = "Add an OpenAI API key to enable Smart Import summaries."
            }

            if autoGenerate {
                await generation.generateSpeech()
            }
        } catch {
            articleSummary = nil
            articleSummaryError = nil
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    coordinator.errorMessage = "No internet connection. Check your network and try again."
                case .timedOut:
                    coordinator.errorMessage = "The request timed out. Try again in a moment."
                default:
                    coordinator.errorMessage = "Failed to load the page. (\(urlError.code.rawValue))"
                }
            } else {
                coordinator.errorMessage = "Failed to import content: \(error.localizedDescription)"
            }
        }
    }

    func replaceEditorWithCondensedImport() {
        guard let coordinator else { return }
        guard let condensed = condensedImportPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !condensed.isEmpty else { return }

        let limit = settings.characterLimit(for: settings.selectedProvider)
        if condensed.count > limit {
            coordinator.inputText = String(condensed.prefix(limit))
            coordinator.errorMessage = "Condensed article exceeded \(settings.formattedCharacterLimit(for: settings.selectedProvider)) characters and was truncated."
        } else {
            coordinator.inputText = condensed
        }
    }

    func insertSummaryIntoEditor() {
        guard let coordinator else { return }
        guard let summary = articleSummaryPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return }

        if coordinator.inputText.isEmpty {
            coordinator.inputText = summary
            return
        }

        var builder = coordinator.inputText
        if !builder.hasSuffix("\n") {
            builder += "\n\n"
        } else if !builder.hasSuffix("\n\n") {
            builder += "\n"
        }

        let composed = builder + summary

        let limit = settings.characterLimit(for: settings.selectedProvider)
        guard composed.count <= limit else {
            coordinator.errorMessage = "Summary would exceed the \(settings.formattedCharacterLimit(for: settings.selectedProvider)) character limit."
            return
        }

        coordinator.inputText = composed
    }

    func normalizeImportedText(_ text: String) -> String {
        TextSanitizer.cleanImportedText(text)
    }
}
