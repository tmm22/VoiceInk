import SwiftUI

struct TextToSpeechView: View {
    @ObservedObject var viewModel: TTSViewModel

    var body: some View {
        TTSWorkspaceView()
            .environmentObject(viewModel)
            .environmentObject(viewModel.transcription)
            .environmentObject(viewModel.playback)
            .environmentObject(viewModel.history)
            .environmentObject(viewModel.generation)
            .environmentObject(viewModel.preview)
            .environmentObject(viewModel.settings)
            .environmentObject(viewModel.importExport)
    }
}

struct TextToSpeechRootView: View {
    @StateObject private var viewModel = TTSViewModel()

    var body: some View {
        TextToSpeechView(viewModel: viewModel)
    }
}

#Preview {
    TextToSpeechView(viewModel: TTSViewModel())
}
