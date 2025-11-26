import SwiftUI
import SwiftData

struct TranscriptionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var expandedTranscription: Transcription?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    @State private var isViewCurrentlyVisible = false
    @State private var showAnalysisView = false
    @StateObject private var viewModel: TranscriptionHistoryViewModel
    
    private let exportService = TranscriptionExportService()
    
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: TranscriptionHistoryViewModel(modelContext: modelContext))
    }
    
    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]
    
    // Static function to create the FetchDescriptor for the latest transcription indicator
    private static func createLatestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            predicate: #Predicate<Transcription> { transcription in
                transcription.isDeleted == false
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
    
    // Cursor-based query descriptor retained for select-all operations
    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        if let timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(searchText) ||
                     (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    transcription.timestamp < timestamp && transcription.isDeleted == false
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp && transcription.isDeleted == false
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                (transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                transcription.isDeleted == false
            }
        } else {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.isDeleted == false
            }
        }

        return descriptor
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: VoiceInkSpacing.lg) {
                searchBar
                historyContent
            }
            .padding(VoiceInkSpacing.lg)

            if !selectedTranscriptions.isEmpty {
                selectionToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: selectedTranscriptions.count)
            }
        }
        .alert(Localization.Trash.moveToTrashConfirmTitle, isPresented: $showDeleteConfirmation) {
            Button(Localization.Trash.moveToTrash, role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Localization.Trash.moveToTrashConfirmMessage(count: selectedTranscriptions.count))
        }
        .sheet(isPresented: $showAnalysisView) {
            if !selectedTranscriptions.isEmpty {
                PerformanceAnalysisView(transcriptions: Array(selectedTranscriptions))
            }
        }
        .onAppear {
            isViewCurrentlyVisible = true
            Task {
                await viewModel.loadInitialContent(searchText: searchText)
            }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
        }
        .onChange(of: searchText) { _, _ in
            Task {
                viewModel.reset()
                await viewModel.loadInitialContent(searchText: searchText)
            }
        }
        // Improved change detection for new transcriptions
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return } // Only proceed if the view is visible

            // Check if a new transcription was added or the latest one changed
            if newId != oldId {
                Task {
                    viewModel.reset()
                    await viewModel.loadInitialContent(searchText: searchText)
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if viewModel.displayedTranscriptions.isEmpty && !viewModel.isLoading {
            emptyStateView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: VoiceInkSpacing.md) {
                        ForEach(viewModel.displayedTranscriptions) { transcription in
                            TranscriptionCard(
                                transcription: transcription,
                                isExpanded: expandedTranscription == transcription,
                                isSelected: selectedTranscriptions.contains(transcription),
                                onDelete: { deleteTranscription(transcription) },
                                onToggleSelection: { toggleSelection(transcription) }
                            )
                            .id(transcription)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if expandedTranscription == transcription {
                                        expandedTranscription = nil
                                    } else {
                                        expandedTranscription = transcription
                                    }
                                }
                            }
                        }

                        if viewModel.hasMoreContent {
                            loadMoreButton
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: expandedTranscription)
                    .padding(.horizontal, VoiceInkSpacing.lg)
                    .padding(.bottom, selectedTranscriptions.isEmpty ? VoiceInkSpacing.lg : 80)
                }
                .padding(.vertical, VoiceInkSpacing.md)
                .onChange(of: expandedTranscription) { _, newValue in
                    if let transcription = newValue {
                        proxy.scrollTo(transcription, anchor: nil)
                    }
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search transcriptions", text: $searchText)
                .font(.system(size: 16, weight: .regular, design: .default))
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(.horizontal, VoiceInkSpacing.md)
        .padding(.vertical, VoiceInkSpacing.sm)
        .voiceInkCardBackground()
    }
    
    private var emptyStateView: some View {
        VStack {
            Spacer()
            VoiceInkCard(padding: VoiceInkSpacing.xl) {
                VStack(spacing: VoiceInkSpacing.md) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No transcriptions found")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Your history will appear here")
                        .voiceInkSubheadline()
                }
            }
            .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadMoreButton: some View {
        Button(action: {
            Task { await viewModel.loadMoreContent(searchText: searchText) }
        }) {
            HStack(spacing: VoiceInkSpacing.xs) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.isLoading ? "Loading..." : "Load More")
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, VoiceInkSpacing.sm)
            .voiceInkCardBackground()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .padding(.top, VoiceInkSpacing.sm)
    }
    
    private var selectionToolbar: some View {
        HStack(spacing: VoiceInkSpacing.sm) {
            Text("\(selectedTranscriptions.count) selected")
                .voiceInkSubheadline()

            Spacer()

            Button {
                showAnalysisView = true
            } label: {
                Label("Analyze", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(SecondaryBorderedButtonStyle())

            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button(action: {
                        exportService.exportTranscriptions(Array(selectedTranscriptions), format: format)
                    }) {
                        Label(format.rawValue, systemImage: iconForFormat(format))
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, VoiceInkSpacing.lg)
                    .padding(.vertical, VoiceInkSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium, style: .continuous)
                            .fill(VoiceInkTheme.Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium, style: .continuous)
                            .stroke(VoiceInkTheme.Card.stroke, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(SecondaryBorderedButtonStyle(tint: .red))

            if selectedTranscriptions.count < viewModel.displayedTranscriptions.count {
                Button("Select All") {
                    Task { await selectAllTranscriptions() }
                }
                .buttonStyle(SecondaryBorderedButtonStyle())
            } else {
                Button("Deselect All") {
                    selectedTranscriptions.removeAll()
                }
                .buttonStyle(SecondaryBorderedButtonStyle())
            }
        }
        .padding(VoiceInkSpacing.md)
        .voiceInkCardBackground(cornerRadius: VoiceInkRadius.large)
        .shadow(color: VoiceInkTheme.Shadow.subtle, radius: 18, x: 0, y: 6)
        .padding(.horizontal, VoiceInkSpacing.lg)
        .padding(.bottom, VoiceInkSpacing.lg)
    }
    
    private func deleteTranscription(_ transcription: Transcription) {
        Task {
            await viewModel.deleteTranscription(transcription)
            if expandedTranscription == transcription {
                expandedTranscription = nil
            }
            selectedTranscriptions.remove(transcription)
            await viewModel.loadInitialContent(searchText: searchText)
        }
    }
    
    private func deleteSelectedTranscriptions() {
        let items = Array(selectedTranscriptions)
        Task {
            await viewModel.deleteTranscriptions(items)
            selectedTranscriptions.removeAll()
            if let expanded = expandedTranscription, items.contains(expanded) {
                expandedTranscription = nil
            }
            await viewModel.loadInitialContent(searchText: searchText)
        }
    }
    
    private func toggleSelection(_ transcription: Transcription) {
        if selectedTranscriptions.contains(transcription) {
            selectedTranscriptions.remove(transcription)
        } else {
            selectedTranscriptions.insert(transcription)
        }
    }
    
    // Modified function to select all transcriptions in the database
    private func selectAllTranscriptions() async {
        do {
            // Create a descriptor without pagination limits to get all IDs
            var allDescriptor = FetchDescriptor<Transcription>()
            
            // Apply search filter if needed
            if !searchText.isEmpty {
                allDescriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
                }
            }
            
            // For better performance, only fetch the IDs
            allDescriptor.propertiesToFetch = [\.id]
            
            // Fetch all matching transcriptions
            let allTranscriptions = try modelContext.fetch(allDescriptor)
            
            let visibleIds = Set(viewModel.displayedTranscriptions.map { $0.id })
            
            // Add all transcriptions to the selection
            await MainActor.run {
                // First add all visible transcriptions directly
                selectedTranscriptions = Set(viewModel.displayedTranscriptions)
                
                // Then add any non-visible transcriptions by ID
                for transcription in allTranscriptions {
                    if !visibleIds.contains(transcription.id) {
                        selectedTranscriptions.insert(transcription)
                    }
                }
            }
        } catch {
            AppLogger.storage.error("Failed to select all transcriptions: \(error.localizedDescription)")
        }
    }
    
    private func iconForFormat(_ format: ExportFormat) -> String {
        switch format {
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .txt: return "doc.text"
        }
    }
}

struct CircularCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(configuration.isOn ? .blue : .gray)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
    }
}
