import SwiftUI
import AppKit

// MARK: - Main Composer Column

struct MainComposerColumn: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let isCompact: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    @Binding var selectedContextPanel: ContextPanelDestination?
    @Binding var activeUtility: ComposerUtility?
    let focusInspector: () -> Void
    @State private var showingTranslationDetail = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                composerStack()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingTranslationDetail) {
            if let translation = viewModel.translationResult {
                TranslationComparisonView(translation: translation)
                    .environmentObject(viewModel)
                    .frame(minWidth: 600, minHeight: 420)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func composerStack() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if isCompact {
                ContextSwitcher(selectedContext: $selectedContextPanel)

                if let selection = selectedContextPanel {
                    ContextPanelCard(selection: selection)
                }
            }

            ComposerUtilityBar(activeUtility: $activeUtility)

            if let utility = activeUtility {
                UtilityDetailView(utility: utility, dismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeUtility = nil
                    }
                })
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            TextEditorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ContextShelfView(showingTranslationDetail: $showingTranslationDetail,
                             focusInspector: focusInspector)

            GenerationStatusFooter(focusInspector: focusInspector)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Context Shelf View

struct ContextShelfView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var importExport: TTSImportExportViewModel
    @Binding var showingTranslationDetail: Bool
    let focusInspector: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if importExport.articleSummary != nil || importExport.isSummarizingArticle || importExport.articleSummaryError != nil {
                ArticleSummaryCard()
            }

            if let translation = viewModel.translationResult, viewModel.translationKeepOriginal {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Translation", systemImage: "globe")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(translation.targetLanguageDisplayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(translation.translatedText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(3)

                    HStack {
                        Button("Use Translation") {
                            viewModel.adoptTranslationAsInput()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("View Details") {
                            showingTranslationDetail = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    CardBackground(isSelected: false)
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Cost Estimate", systemImage: "dollarsign.circle")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(viewModel.costEstimateSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let detail = viewModel.costEstimateDetail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                } else {
                    Text("Estimate reflects your current provider and text length.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }

                HStack {
                    Spacer()
                    Button("Open Inspector") {
                        focusInspector()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                CardBackground(isSelected: false)
            )
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.translationResult)
    }
}

// MARK: - Article Summary Card

struct ArticleSummaryCard: View {
    @EnvironmentObject var importExport: TTSImportExportViewModel
    @EnvironmentObject var generation: TTSSpeechGenerationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Smart Import", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let host = importExport.articleSummary?.sourceURL.host {
                    Text(host)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if importExport.isSummarizingArticle {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Cleaning the article with AI…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let summary = importExport.articleSummaryPreview {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(4)
            } else if let error = importExport.articleSummaryError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text("Use Import to pull a web article and see an AI summary here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let reduction = importExport.articleSummaryReductionDescription {
                Text(reduction)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Use Concise Article") {
                    importExport.replaceEditorWithCondensedImport()
                }
                .buttonStyle(.bordered)
                .disabled(!importExport.canAdoptCondensedImport)

                Button("Insert Summary") {
                    importExport.insertSummaryIntoEditor()
                }
                .buttonStyle(.bordered)
                .disabled(!importExport.canInsertSummaryIntoEditor)

                Spacer()

                Button("Speak Summary") {
                    Task {
                        await importExport.speakSummaryOfImportedArticle()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!importExport.canSpeakSummary || generation.isGenerating)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CardBackground(isSelected: false)
        )
        .animation(.easeInOut(duration: 0.2), value: importExport.isSummarizingArticle)
        .animation(.easeInOut(duration: 0.2), value: importExport.articleSummary)
    }
}

// MARK: - Generation Status Footer

struct GenerationStatusFooter: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var generation: TTSSpeechGenerationViewModel
    let focusInspector: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if generation.isGenerating {
                HStack(spacing: 6) {
                    ProgressView(value: generation.generationProgress)
                        .frame(width: 100)
                    Text("Generating…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                focusInspector()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle")
                        .imageScale(.small)
                    Text(viewModel.costEstimate.summary)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("View detailed cost estimate")
        }
        .padding(.vertical, 4)
    }
}
