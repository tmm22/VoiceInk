import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @ObservedObject private var starPrompt = GitHubStarPromptCoordinator.shared

    var body: some View {
        DashboardContent(modelContext: modelContext)
        .overlay(alignment: .bottomTrailing) {
            if starPrompt.isVisible {
                GitHubStarPromptCard(
                    isBusy: starPrompt.isStarring,
                    completionState: starPrompt.completionState,
                    openFailed: starPrompt.openFailed,
                    onStar: { starPrompt.star() },
                    onLater: { starPrompt.later() }
                )
                // True corner anchor, sitting over Copy System Info rather than making room for it.
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: starPrompt.isVisible)
    }
}
