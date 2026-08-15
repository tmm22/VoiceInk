import SwiftUI

struct ONNXLocalModelCardView: View {
    let model: any TranscriptionModel
    let deleteAction: () -> Void
    let downloadAction: () -> Void

    @ObservedObject private var modelManager = ONNXLocalModelManager.shared

    private var isDownloaded: Bool {
        modelManager.isModelDownloaded(model)
    }

    private var isDownloading: Bool {
        modelManager.activeDownloads.contains(model.name)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.provider == .senseVoice ? "waveform.badge.magnifyingglass" : "waveform.path")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if isDownloading {
                ProgressView(value: modelManager.downloadProgress[model.name] ?? 0)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .accessibilityLabel(String(format: String(localized: "Downloading %@"), model.displayName))
            } else if isDownloaded {
                Menu {
                    Button(String(localized: "Show in Finder")) {
                        modelManager.showInFinder(model)
                    }
                    Button(String(localized: "Delete"), role: .destructive, action: deleteAction)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            } else {
                Button(String(localized: "Download"), action: downloadAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(AppMaterialCardBackground(cornerRadius: 10))
    }
}
