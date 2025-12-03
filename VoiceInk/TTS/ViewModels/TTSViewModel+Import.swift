import SwiftUI
import AVFoundation

// MARK: - URL Import and Article Summarization
extension TTSViewModel {
    func importText(from urlString: String, autoGenerate: Bool) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorMessage = "Enter a URL to import content."
            return
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            errorMessage = "URL must start with http:// or https://."
            return
        }

        isImportingFromURL = true
        errorMessage = nil
        defer { isImportingFromURL = false }

        do {
            let rawText = try await urlContentLoader.fetchPlainText(from: url)
            let normalized = normalizeImportedText(rawText)

            guard !normalized.isEmpty else {
                errorMessage = "Unable to find readable text at that address."
                articleSummary = nil
                return
            }

            let limit = characterLimit(for: selectedProvider)
            let formattedLimit = formattedCharacterLimit(for: selectedProvider)
            let segments = TextChunker.chunk(text: normalized, limit: limit)

            guard let firstSegment = segments.first else {
                errorMessage = "Unable to find readable text at that address."
                articleSummary = nil
                return
            }

            let preparedText: String
            if segments.count > 1 {
                let separator = "\n\n\(batchDelimiterToken)\n\n"
                preparedText = segments.joined(separator: separator)
                errorMessage = nil
            } else if firstSegment.count > limit {
                preparedText = String(firstSegment.prefix(limit))
                errorMessage = "Imported text exceeded \(formattedLimit) characters. The content was truncated."
            } else {
                preparedText = firstSegment
                errorMessage = nil
            }

            inputText = preparedText

            articleSummaryTask?.cancel()
            articleSummary = ArticleImportSummary.make(sourceURL: url, originalText: normalized)
            articleSummaryError = nil

            if canSummarizeImports {
                let summarySource = normalized
                articleSummaryTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.generateArticleSummary(for: summarySource, url: url)
                    self.articleSummaryTask = nil
                }
            } else {
                articleSummaryError = "Add an OpenAI API key to enable Smart Import summaries."
            }

            if autoGenerate {
                await generateSpeech()
            }
        } catch {
            articleSummary = nil
            articleSummaryError = nil
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    errorMessage = "No internet connection. Check your network and try again."
                case .timedOut:
                    errorMessage = "The request timed out. Try again in a moment."
                default:
                    errorMessage = "Failed to load the page. (\(urlError.code.rawValue))"
                }
            } else {
                errorMessage = "Failed to import content: \(error.localizedDescription)"
            }
        }

    }

    func replaceEditorWithCondensedImport() {
        guard let condensed = condensedImportPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !condensed.isEmpty else { return }

        let limit = characterLimit(for: selectedProvider)
        if condensed.count > limit {
            inputText = String(condensed.prefix(limit))
            errorMessage = "Condensed article exceeded \(formattedCharacterLimit(for: selectedProvider)) characters and was truncated."
        } else {
            inputText = condensed
        }
    }

    func insertSummaryIntoEditor() {
        guard let summary = articleSummaryPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return }

        if inputText.isEmpty {
            inputText = summary
            return
        }

        var builder = inputText
        if !builder.hasSuffix("\n") {
            builder += "\n\n"
        } else if !builder.hasSuffix("\n\n") {
            builder += "\n"
        }

        let composed = builder + summary

        let limit = characterLimit(for: selectedProvider)
        guard composed.count <= limit else {
            errorMessage = "Summary would exceed the \(formattedCharacterLimit(for: selectedProvider)) character limit."
            return
        }

        inputText = composed
    }

    func speakSummaryOfImportedArticle() async {
        guard let summary = articleSummaryPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return }

        stopPreview()

        let providerType = selectedProvider
        let provider = getProvider(for: providerType)
        let voice = selectedVoice ?? provider.defaultVoice
        let format = currentFormatForGeneration()

        isGenerating = true
        errorMessage = nil
        generationProgress = 0

        do {
            let prepared = applyPronunciationRules(to: summary, provider: providerType)
            let output = try await performGeneration(
                text: prepared,
                providerType: providerType,
                voice: voice,
                format: format,
                shouldAutoplay: true
            )

            recordGenerationHistory(
                audioData: output.audioData,
                format: format,
                text: prepared,
                voice: voice,
                provider: providerType,
                duration: output.duration,
                transcript: output.transcript
            )
        } catch let error as TTSError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to generate summary audio: \(error.localizedDescription)"
        }

        isGenerating = false
        generationProgress = 0
    }
}

// MARK: - Import Private Helpers
extension TTSViewModel {
    func normalizeImportedText(_ text: String) -> String {
        TextSanitizer.cleanImportedText(text)
    }

    func generateArticleSummary(for text: String, url: URL) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard canSummarizeImports else { return }

        isSummarizingArticle = true
        articleSummaryError = nil

        defer { isSummarizingArticle = false }

        do {
            let result = try await summarizationService.summarize(text: trimmed, sourceURL: url)
            try Task.checkCancellation()
            applySummarizationResult(result)
        } catch is CancellationError {
            // Task cancelled; silently exit
        } catch let error as TTSError {
            articleSummaryError = error.localizedDescription
        } catch {
            articleSummaryError = "Unable to summarize article: \(error.localizedDescription)"
        }
    }

    func applySummarizationResult(_ result: SummarizationResult) {
        guard var current = articleSummary else { return }

        let condensed = result.condensedArticle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !condensed.isEmpty {
            current.condensedText = condensed
            current.condensedWordCount = ArticleImportSummary.wordCount(in: condensed)
        }

        let summaryText = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summaryText.isEmpty {
            current.summaryText = summaryText
        }

        current.lastUpdated = Date()
        articleSummary = current
        articleSummaryError = nil
    }
}