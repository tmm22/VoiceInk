import SwiftUI

struct BatchQueueView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var generation: TTSSpeechGenerationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: settings.isMinimalistMode ? 8 : 12) {
            header

            if generation.batchItems.isEmpty {
                emptyState
            } else {
                queueList
            }

            if generation.isBatchRunning {
                Button("Cancel Batch", role: .destructive) {
                    generation.cancelBatchGeneration()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(settings.isMinimalistMode ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .animation(.easeInOut(duration: 0.2), value: generation.batchItems)
    }

    private var header: some View {
        HStack {
            Label("Batch Queue", systemImage: "list.bullet.rectangle")
                .font(.headline)

            Spacer()

            if generation.isBatchRunning {
                ProgressView(value: generation.batchProgress)
                    .frame(width: 120)
            } else if viewModel.hasBatchableSegments {
                Text("Detected \(viewModel.pendingBatchSegmentCount) segments")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Separate paragraphs with a line containing only `---` to queue multiple generations.")
                .font(.caption)
                .foregroundColor(.secondary)
            if viewModel.hasBatchableSegments {
                Text("Tap Generate Batch to process all \(viewModel.pendingBatchSegmentCount) segments sequentially.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(generation.batchItems) { item in
                BatchQueueRow(item: item)
            }
        }
    }
}

private struct BatchQueueRow: View {
    let item: BatchGenerationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.status.iconName)
                    .foregroundColor(color(for: item.status))

                Text("Segment \(item.index)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(item.voice.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(item.provider.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(item.previewText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            if case .failed(let message) = item.status {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
        )
    }

    private func color(for status: BatchGenerationItem.Status) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .accentColor
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

struct BatchQueueView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = TTSViewModel()
        BatchQueueView()
            .environmentObject(viewModel)
            .environmentObject(viewModel.settings)
            .environmentObject(viewModel.generation)
            .padding()
            .frame(width: 600)
    }
}
