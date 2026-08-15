import SwiftUI

// MARK: - TTS About Sheet View

struct TTSAboutSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("TTS Workspace")
                .font(.title)
                .fontWeight(.bold)

            Text("Transform text into natural-sounding speech using AI voices from multiple providers.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Divider()
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Label("OpenAI TTS", systemImage: "checkmark.circle.fill")
                Label("ElevenLabs", systemImage: "checkmark.circle.fill")
                Label("Google Cloud TTS", systemImage: "checkmark.circle.fill")
                Label("Local TTS (Offline)", systemImage: "checkmark.circle.fill")
            }
            .font(.callout)
            .foregroundColor(.secondary)

            Spacer()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 400, height: 400)
    }
}
