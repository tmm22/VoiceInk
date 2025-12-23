import SwiftUI
import AppKit

// MARK: - Utility Detail View

struct UtilityDetailView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let utility: ComposerUtility
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(utility.title, systemImage: utility.icon)
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            switch utility {
            case .transcription:
                TranscriptionUtilityView()
                    .environmentObject(viewModel.transcription)
            case .urlImport:
                URLImportView()
                    .environmentObject(viewModel)
            case .sampleText:
                SampleTextUtilityView(onClose: dismiss)
            case .chunking:
                ChunkingHelperView()
            }
        }
        .padding(16)
        .background(
            CardBackground(isSelected: false, cornerRadius: 12)
        )
    }
}

// MARK: - Sample Text Utility View

struct SampleTextUtilityView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace the editor contents with a ready-made sample to test providers quickly.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Button("Short intro paragraph") {
                    viewModel.inputText = "Hello! This is a sample text to demonstrate the text-to-speech functionality. The app supports multiple providers and voices so you can create natural-sounding speech from any text."
                    onClose()
                }
                Button("Demo feature tour") {
                    viewModel.inputText = """
Welcome to the \(AppBrand.communityName) Text-to-Speech workspace! This experience transforms written text into natural-sounding speech using a curated set of AI voices.

Choose between OpenAI, ElevenLabs, Google Cloud, or the offline Tight Ass Mode. Dial in voice style, playback speed, and export format so each narration fits the moment.

Use the playback bar to review every generation, then export exactly what you need for your project or workflow.
"""
                    onClose()
                }
                Button("Long narrative excerpt") {
                    viewModel.inputText = """
The art of text-to-speech synthesis has evolved dramatically over the past decade. What once sounded robotic now feels natural, expressive, and tailored.

Modern providers use deep learning models trained on vast speech corpora. These networks capture intonation, rhythm, pacing, and emotion to produce rich voices on demand.

From accessibility tools to audiobooks, synthetic narration is reshaping how we consume information. \(AppBrand.communityName) brings those capabilities to the desktop so you can experiment, prototype, and deliver high-quality speech quickly.
"""
                    onClose()
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Chunking Helper View

struct ChunkingHelperView: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var segments: [String] {
        viewModel.batchSegments(from: viewModel.inputText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use a line containing only --- to mark breaks between segments. Each segment becomes its own generation in the batch queue.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .foregroundColor(.accentColor)
                Text("Detected segments: \(segments.count)")
                    .font(.subheadline)
            }

            if segments.count <= 1 {
                Text("Add --- on its own line to split the script into multiple parts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Segment \(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(segment.count) chars")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(segment)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.windowBackgroundColor))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Translation Comparison View

struct TranslationComparisonView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let translation: TranslationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label("Translation Preview", systemImage: "globe")
                    .font(.headline)

                Spacer()

                if let detected = viewModel.translationDetectedLanguageDisplayName {
                    Text("Detected: \(detected)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("→ \(translation.targetLanguageDisplayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Use Translation") {
                    viewModel.adoptTranslationAsInput()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Replace the editor text with the translated version")
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                translationColumn(
                    title: "Original",
                    languageLabel: viewModel.translationDetectedLanguageDisplayName ?? "",
                    text: translation.originalText
                )

                translationColumn(
                    title: "Translated",
                    languageLabel: translation.targetLanguageDisplayName,
                    text: translation.translatedText
                )
            }
        }
        .padding(16)
        .background(
            CardBackground(isSelected: false, cornerRadius: 12)
        )
    }

    private func translationColumn(title: String, languageLabel: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !languageLabel.isEmpty {
                        Text(languageLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Copy this text to the clipboard")
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.windowBackgroundColor))
                    )
            }
            .frame(minHeight: 140, maxHeight: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Translation Settings Popover

struct TranslationSettingsPopover: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Translation")
                    .font(.headline)
                Text("Choose a target language and optionally keep the original text alongside the translated copy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Picker("Target language", selection: $viewModel.translationTargetLanguage) {
                ForEach(viewModel.availableTranslationLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)

            Toggle("Keep original text", isOn: $viewModel.translationKeepOriginal)

            if !viewModel.canTranslate {
                Label("Add an OpenAI API key in Settings to enable translation.", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

            Divider()

            HStack {
                Spacer()

                if viewModel.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button {
                    Task {
                        await viewModel.translateCurrentText()
                        isPresented = false
                    }
                } label: {
                    Label("Translate Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isTranslating || !viewModel.canTranslate || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 260)
    }
}

// MARK: - Voice Preview Popover

struct VoicePreviewPopover: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var preview: TTSVoicePreviewViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Preview")
                    .font(.headline)
                Text("Play a short sample for any available voice. Fallback previews synthesize a brief line when no hosted clip is provided.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if settings.availableVoices.isEmpty {
                Text("No voices are available for the selected provider.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(settings.availableVoices) { voice in
                            Button {
                                preview.previewVoice(voice)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .center, spacing: 8) {
                                        Text(voice.name)
                                            .fontWeight(preview.isPreviewingVoice(voice) ? .semibold : .regular)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        previewStatusIcon(for: voice)
                                    }

                                    Text(voice.language)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if !preview.canPreview(voice) {
                                        Text("Add an API key in Settings to preview this voice.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(rowBackground(for: voice))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(rowBorderColor(for: voice), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!preview.canPreview(voice))
                            .opacity(preview.canPreview(voice) ? 1 : 0.55)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .frame(maxHeight: 260)
            }

            if preview.isPreviewActive {
                Divider()
                Button {
                    preview.stopPreview()
                } label: {
                    Label("Stop Preview", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    private func rowBackground(for voice: Voice) -> some ShapeStyle {
        if preview.isPreviewingVoice(voice) || preview.isPreviewLoadingVoice(voice) {
            return Color.accentColor.opacity(0.15)
        }
        return Color.clear
    }

    private func rowBorderColor(for voice: Voice) -> Color {
        if preview.isPreviewingVoice(voice) || preview.isPreviewLoadingVoice(voice) {
            return Color.accentColor.opacity(0.4)
        }
        return Color.secondary.opacity(0.3)
    }

    @ViewBuilder
    private func previewStatusIcon(for voice: Voice) -> some View {
        if preview.isPreviewLoadingVoice(voice) {
            ProgressView()
                .controlSize(.small)
        } else if preview.isPreviewingVoice(voice) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundColor(.accentColor)
        } else if preview.canPreview(voice) {
            Image(systemName: "play.circle")
                .foregroundColor(.secondary)
        } else {
            Image(systemName: "key.slash")
                .foregroundColor(.secondary)
        }
    }
}
