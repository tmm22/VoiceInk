import SwiftUI
import AppKit

struct RecentGenerationsView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var history: TTSHistoryViewModel
    @EnvironmentObject var generation: TTSSpeechGenerationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: settings.isMinimalistMode ? 8 : 12) {
            HStack {
                Label("Recent Generations", systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                Spacer()

                if !history.recentGenerations.isEmpty {
                    Button("Clear", role: .destructive) {
                        history.clearHistory()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(history.recentGenerations.isEmpty)
                }
            }

            if history.recentGenerations.isEmpty {
                Text("Generated audio will appear here for quick reuse.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(history.recentGenerations) { item in
                    HistoryRow(item: item)
                        .transition(.opacity)
                }
            }
        }
        .padding(settings.isMinimalistMode ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .animation(.easeInOut(duration: 0.2), value: history.recentGenerations)
    }
}

private struct HistoryRow: View {
    @EnvironmentObject var importExport: TTSImportExportViewModel
    @EnvironmentObject var history: TTSHistoryViewModel
    @EnvironmentObject var generation: TTSSpeechGenerationViewModel
    let item: GenerationHistoryItem
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.provider.icon)
                    .foregroundColor(.accentColor)

                Text(item.textPreview.isEmpty ? "(No text)" : item.textPreview)
                    .font(.subheadline)
                    .lineLimit(2)

                Spacer()

                Text("\(item.voice.name) • \(item.format.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Label(item.formattedDuration, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label(item.formattedTimestamp, systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    Task {
                        await history.playHistoryItem(item)
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Play this generated audio")
                .disabled(generation.isGenerating)

                Button {
                    history.exportHistoryItem(item)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Export this generated audio")

                if item.transcript != nil {
                    Menu {
                        Button("Export SRT") {
                            importExport.exportTranscript(for: item, format: .srt)
                        }
                        Button("Export VTT") {
                            importExport.exportTranscript(for: item, format: .vtt)
                        }
                    } label: {
                        Label("Transcript", systemImage: "doc.text")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Export transcript for this audio")
                }

                Button(role: .destructive) {
                    history.removeHistoryItem(item)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Remove from recent list")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color(NSColor.windowBackgroundColor).opacity(0.6) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct RecentGenerationsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = TTSViewModel()
        RecentGenerationsView()
            .environmentObject(viewModel)
            .environmentObject(viewModel.settings)
            .environmentObject(viewModel.history)
            .environmentObject(viewModel.generation)
            .environmentObject(viewModel.importExport)
            .padding()
            .frame(width: 600)
    }
}
