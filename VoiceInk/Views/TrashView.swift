import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TrashViewModel
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showEmptyTrashConfirmation = false
    @State private var showDeleteConfirmation = false
    
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: TrashViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            if viewModel.deletedTranscriptions.isEmpty {
                emptyStateView
            } else {
                trashContent
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(VoiceInkTheme.Palette.canvas)
        .onAppear {
            Task {
                await viewModel.loadDeletedTranscriptions()
            }
        }
        .alert("\(Localization.Trash.emptyTrash)?", isPresented: $showEmptyTrashConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(Localization.Trash.emptyTrash, role: .destructive) {
                Task {
                    await viewModel.emptyTrash()
                }
            }
        } message: {
            Text("This will permanently delete \(viewModel.deletedTranscriptions.count) item(s). This action cannot be undone.")
        }
        .alert("Delete Permanently?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.permanentlyDeleteTranscriptions(Array(selectedTranscriptions))
                    selectedTranscriptions.removeAll()
                }
            }
        } message: {
            Text("This will permanently delete \(selectedTranscriptions.count) item(s). This action cannot be undone.")
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Localization.Trash.title)
                    .font(.system(size: 20, weight: .semibold))
                Text("\(viewModel.deletedTranscriptions.count) item(s) - \(Localization.Trash.retentionInfo)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !viewModel.deletedTranscriptions.isEmpty {
                Button(Localization.Trash.emptyTrash) {
                    showEmptyTrashConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(VoiceInkTheme.Palette.surface)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: VoiceInkSpacing.md) {
            Spacer()
            Image(systemName: "trash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(Localization.Trash.trashIsEmpty)
                .font(.system(size: 18, weight: .semibold))
            Text(Localization.Trash.trashEmptyDescription)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var trashContent: some View {
        VStack(spacing: 0) {
            if !selectedTranscriptions.isEmpty {
                selectionToolbar
            }
            
            ScrollView {
                LazyVStack(spacing: VoiceInkSpacing.sm) {
                    ForEach(viewModel.deletedTranscriptions) { transcription in
                        TrashItemCard(
                            transcription: transcription,
                            isSelected: selectedTranscriptions.contains(transcription),
                            onRestore: {
                                Task {
                                    await viewModel.restoreTranscription(transcription)
                                    NotificationManager.shared.showNotification(
                                        title: Localization.Trash.restored,
                                        type: .success
                                    )
                                }
                            },
                            onDelete: {
                                selectedTranscriptions = [transcription]
                                showDeleteConfirmation = true
                            },
                            onToggleSelection: {
                                toggleSelection(transcription)
                            }
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    private var selectionToolbar: some View {
        HStack(spacing: VoiceInkSpacing.sm) {
            Text("\(selectedTranscriptions.count) selected")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button {
                Task {
                    await viewModel.restoreTranscriptions(Array(selectedTranscriptions))
                    selectedTranscriptions.removeAll()
                    NotificationManager.shared.showNotification(
                        title: Localization.Trash.restoredMultiple,
                        type: .success
                    )
                }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            
            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            
            Button("Deselect All") {
                selectedTranscriptions.removeAll()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(VoiceInkTheme.Palette.surface)
    }
    
    private func toggleSelection(_ transcription: Transcription) {
        if selectedTranscriptions.contains(transcription) {
            selectedTranscriptions.remove(transcription)
        } else {
            selectedTranscriptions.insert(transcription)
        }
    }
}

struct TrashItemCard: View {
    let transcription: Transcription
    let isSelected: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    let onToggleSelection: () -> Void
    
    private var deletedTimeAgo: String {
        guard let deletedAt = transcription.deletedAt else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: deletedAt, relativeTo: Date())
    }
    
    private var daysUntilPermanentDeletion: Int {
        guard let deletedAt = transcription.deletedAt else { return 30 }
        let daysSinceDeletion = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        return max(0, 30 - daysSinceDeletion)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: VoiceInkSpacing.md) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: VoiceInkSpacing.xs) {
                Text(transcription.text)
                    .lineLimit(2)
                    .font(.system(size: 14))
                
                HStack(spacing: VoiceInkSpacing.sm) {
                    Label("Deleted \(deletedTimeAgo)", systemImage: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("\(daysUntilPermanentDeletion) days until permanent deletion")
                        .font(.system(size: 11))
                        .foregroundColor(daysUntilPermanentDeletion <= 7 ? .orange : .secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: VoiceInkSpacing.xs) {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .help("Restore")
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Delete permanently")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                .fill(isSelected ? VoiceInkTheme.Palette.elevatedSurface : VoiceInkTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                .stroke(isSelected ? Color.accentColor : VoiceInkTheme.Card.stroke, lineWidth: 1)
        )
    }
}

@MainActor
final class TrashViewModel: ObservableObject {
    @Published private(set) var deletedTranscriptions: [Transcription] = []
    @Published private(set) var isLoading = false
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func loadDeletedTranscriptions() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            var descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.isDeleted == true
                },
                sortBy: [SortDescriptor(\Transcription.deletedAt, order: .reverse)]
            )
            deletedTranscriptions = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.storage.error("Failed to load deleted transcriptions: \(error.localizedDescription)")
        }
    }
    
    func restoreTranscription(_ transcription: Transcription) async {
        transcription.restore()
        deletedTranscriptions.removeAll { $0.id == transcription.id }
        
        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to restore transcription: \(error.localizedDescription)")
        }
    }
    
    func restoreTranscriptions(_ transcriptions: [Transcription]) async {
        transcriptions.forEach { $0.restore() }
        deletedTranscriptions.removeAll { transcription in
            transcriptions.contains(where: { $0.id == transcription.id })
        }
        
        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to restore transcriptions: \(error.localizedDescription)")
        }
    }
    
    func permanentlyDeleteTranscription(_ transcription: Transcription) async {
        removeAssociatedAudio(for: transcription)
        modelContext.delete(transcription)
        deletedTranscriptions.removeAll { $0.id == transcription.id }
        
        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to permanently delete transcription: \(error.localizedDescription)")
        }
    }
    
    func permanentlyDeleteTranscriptions(_ transcriptions: [Transcription]) async {
        transcriptions.forEach(removeAssociatedAudio)
        transcriptions.forEach(modelContext.delete)
        deletedTranscriptions.removeAll { transcription in
            transcriptions.contains(where: { $0.id == transcription.id })
        }
        
        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to permanently delete transcriptions: \(error.localizedDescription)")
        }
    }
    
    func emptyTrash() async {
        deletedTranscriptions.forEach(removeAssociatedAudio)
        deletedTranscriptions.forEach(modelContext.delete)
        deletedTranscriptions.removeAll()
        
        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to empty trash: \(error.localizedDescription)")
        }
    }
    
    private func removeAssociatedAudio(for transcription: Transcription) {
        guard let urlString = transcription.audioFileURL,
              let url = URL(string: urlString) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
