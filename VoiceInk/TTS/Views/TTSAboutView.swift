import SwiftUI

// MARK: - About View
struct TTSAboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("\(AppBrand.communityName) Text-to-Speech")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Integrated text-to-speech workspace for the \(AppBrand.communityName) build.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Divider()
                .frame(width: 200)
            
            VStack(alignment: .leading, spacing: 8) {
                if let documentationURL = AppConfiguration.documentationURL {
                    Link("Documentation", destination: documentationURL)
                }
                if let issueTrackerURL = AppConfiguration.issueTrackerURL {
                    Link("Report an Issue", destination: issueTrackerURL)
                }
                if let privacyPolicyURL = AppConfiguration.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacyPolicyURL)
                }
            }
            
            Spacer()
            
            Text("© 2025 \(AppBrand.communityName) contributors.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview
#Preview {
    TTSAboutView()
}
