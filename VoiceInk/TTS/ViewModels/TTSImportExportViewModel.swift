import SwiftUI
import Foundation

@MainActor
protocol TTSImportExportCoordinating: AnyObject {
    var inputText: String { get set }
    var errorMessage: String? { get set }
    var audioData: Data? { get set }
    var currentAudioFormat: AudioSettings.AudioFormat { get set }
    var currentTranscript: TranscriptBundle? { get set }

    func stopPreview()
}

@MainActor
final class TTSImportExportViewModel: ObservableObject {
    @Published var isImportingFromURL: Bool = false
    @Published var articleSummary: ArticleImportSummary?
    @Published var isSummarizingArticle: Bool = false
    @Published var articleSummaryError: String?

    weak var coordinator: (any TTSImportExportCoordinating)?

    let settings: TTSSettingsViewModel
    let playback: TTSPlaybackViewModel
    let history: TTSHistoryViewModel
    let generation: TTSSpeechGenerationViewModel
    let urlContentLoader: URLContentLoading
    let summarizationService: TextSummarizationService
    let batchDelimiterToken: String

    var articleSummaryTask: Task<Void, Never>?

    init(
        settings: TTSSettingsViewModel,
        playback: TTSPlaybackViewModel,
        history: TTSHistoryViewModel,
        generation: TTSSpeechGenerationViewModel,
        urlContentLoader: URLContentLoading,
        summarizationService: TextSummarizationService,
        batchDelimiterToken: String
    ) {
        self.settings = settings
        self.playback = playback
        self.history = history
        self.generation = generation
        self.urlContentLoader = urlContentLoader
        self.summarizationService = summarizationService
        self.batchDelimiterToken = batchDelimiterToken
    }

    deinit {
        articleSummaryTask?.cancel()
    }
}
