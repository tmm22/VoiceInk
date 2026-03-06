import SwiftUI
import SwiftData

@available(*, deprecated, message: "Use TranscriptionHistoryView as the single history implementation.")
struct TranscriptionHistoryLegacyView: View {
    private let modelContainer: ModelContainer?

    init(modelContext: ModelContext) {
        self.modelContainer = modelContext.container
    }

    init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer
    }

    var body: some View {
        if let modelContainer {
            TranscriptionHistoryView()
                .modelContainer(modelContainer)
        } else {
            TranscriptionHistoryView()
        }
    }
}
