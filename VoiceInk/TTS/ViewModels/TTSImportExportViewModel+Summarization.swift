import Foundation

extension TTSImportExportViewModel {
    func speakSummaryOfImportedArticle() async {
        guard let coordinator else { return }
        guard let summary = articleSummaryPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return }

        coordinator.stopPreview()

        let providerType = settings.selectedProvider
        let provider = settings.getProvider(for: providerType)
        let voice = settings.selectedVoice ?? provider.defaultVoice
        let format = settings.currentFormatForGeneration()

        generation.isGenerating = true
        coordinator.errorMessage = nil
        generation.generationProgress = 0

        do {
            let prepared = settings.applyPronunciationRules(to: summary, provider: providerType)
            let output = try await generation.performGeneration(
                text: prepared,
                providerType: providerType,
                voice: voice,
                format: format,
                shouldAutoplay: true
            )

            history.recordGenerationHistory(
                audioData: output.audioData,
                format: format,
                text: prepared,
                voice: voice,
                provider: providerType,
                duration: output.duration,
                transcript: output.transcript
            )
        } catch let error as TTSError {
            coordinator.errorMessage = error.localizedDescription
        } catch {
            coordinator.errorMessage = "Failed to generate summary audio: \(error.localizedDescription)"
        }

        generation.isGenerating = false
        generation.generationProgress = 0
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
            return
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
