import SwiftUI
import SwiftData

@MainActor
struct OnboardingPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Transcription.self, configurations: configuration)
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
        let whisperState = WhisperState(modelContext: container.mainContext)
        let hotkeyManager = HotkeyManager(whisperState: whisperState)

        return OnboardingPermissionsPreviewWrapper(hotkeyManager: hotkeyManager)
            .environmentObject(hotkeyManager)
            .frame(width: 900, height: 700)
            .preferredColorScheme(.dark)
    }
}

private struct OnboardingPermissionsPreviewWrapper: View {
    @State var hasCompletedOnboarding = false
    let hotkeyManager: HotkeyManager

    var body: some View {
        OnboardingPermissionsView(hasCompletedOnboarding: $hasCompletedOnboarding)
            .environmentObject(hotkeyManager)
    }
}
