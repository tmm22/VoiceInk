import SwiftUI

struct MetricsContent: View {
    let transcriptions: [Transcription]
    @ObservedObject var licenseViewModel: LicenseViewModel
    
    private var licenseState: LicenseViewModel.LicenseState { licenseViewModel.licenseState }
    
    var body: some View {
        Group {
            if transcriptions.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        heroSection
                        metricsSection
                        HStack(alignment: .top, spacing: 18) {
                            HelpAndResourcesSection()
                            DashboardPromotionsSection(licenseState: licenseState)
                        }
                    }
                    .padding(.vertical, 28)
                    .padding(.horizontal, 32)
                }
                .background(Color(.windowBackgroundColor))
                .overlay(alignment: .bottomTrailing) {
                    footerActionsView
                        .padding()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.secondary)
            Text("No Transcriptions Yet")
                .font(.title3.weight(.semibold))
            Text("Start your first recording to unlock insight into your workflow.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Sections
    
    private var heroSection: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                
                (Text("You have saved ")
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.85))
                 +
                 Text(formattedTimeSaved)
                    .fontWeight(.black)
                    .font(.system(size: 36, design: .rounded))
                    .foregroundStyle(.white)
                 +
                 Text(" with VoiceLink Community")
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.85))
                )
                .font(.system(size: 30))
                .multilineTextAlignment(.center)
                
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            
            Text(heroSubtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 30, x: 0, y: 16)
    }
    
    private var metricsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            MetricCard(
                icon: "mic.fill",
                title: "Sessions Recorded",
                value: "\(transcriptions.count)",
                detail: "VoiceLink Community sessions completed",
                color: .purple
            )
            
            MetricCard(
                icon: "text.alignleft",
                title: "Words Dictated",
                value: Formatters.formattedNumber(totalWordsTranscribed),
                detail: "words generated across your sessions",
                color: Color(nsColor: .controlAccentColor)
            )
            
            MetricCard(
                icon: "speedometer",
                title: "Words Per Minute",
                value: averageWordsPerMinute > 0
                    ? String(format: "%.1f", averageWordsPerMinute)
                    : "–",
                detail: "VoiceLink vs. typing by hand",
                color: .yellow
            )
            
            MetricCard(
                icon: "keyboard.fill",
                title: "Keystrokes Saved",
                value: Formatters.formattedNumber(totalKeystrokesSaved),
                detail: "estimated fewer keystrokes typed",
                color: .orange
            )
        }
    }
    
    private var footerActionsView: some View {
        HStack(spacing: 12) {
            CopySystemInfoButton()
            feedbackButton
        }
    }
    
    private var feedbackButton: some View {
        Button(action: {
            EmailSupport.openSupportEmail()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble.fill")
                Text("Feedback or Issues?")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
    }
    
    private var formattedTimeSaved: String {
        Formatters.formattedDuration(timeSaved, style: .full, fallback: "Time savings on the way")
    }
    
    private var heroSubtitle: String {
        guard !transcriptions.isEmpty else {
            return "Your VoiceLink Community journey starts with your first recording."
        }
        
        let wordsText = Formatters.formattedNumber(totalWordsTranscribed)
        let sessionCount = transcriptions.count
        let sessionText = sessionCount == 1 ? "session" : "sessions"
        
        if let firstDate = firstTranscriptionDateText {
            return "Dictated \(wordsText) words across \(sessionCount) \(sessionText) since \(firstDate)."
        }
        
        return "Dictated \(wordsText) words across \(sessionCount) \(sessionText)."
    }
    
    private var heroGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(nsColor: .controlAccentColor),
                Color(nsColor: .controlAccentColor).opacity(0.85),
                Color(nsColor: .controlAccentColor).opacity(0.7)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Computed Metrics
    
    private var totalWordsTranscribed: Int {
        transcriptions.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
    
    private var totalRecordedTime: TimeInterval {
        transcriptions.reduce(0) { $0 + $1.duration }
    }
    
    private var estimatedTypingTime: TimeInterval {
        let averageTypingSpeed: Double = 35 // words per minute
        let totalWords = Double(totalWordsTranscribed)
        let estimatedTypingTimeInMinutes = totalWords / averageTypingSpeed
        return estimatedTypingTimeInMinutes * 60
    }
    
    private var timeSaved: TimeInterval {
        max(estimatedTypingTime - totalRecordedTime, 0)
    }
    
    private var averageWordsPerMinute: Double {
        guard totalRecordedTime > 0 else { return 0 }
        return Double(totalWordsTranscribed) / (totalRecordedTime / 60.0)
    }
    
    private var totalKeystrokesSaved: Int {
        Int(Double(totalWordsTranscribed) * 5.0)
    }
    
    private var firstTranscriptionDateText: String? {
        guard let firstDate = transcriptions.map(\.timestamp).min() else { return nil }
        return dateFormatter.string(from: firstDate)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

private enum Formatters {
    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
    static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        return formatter
    }()
    
    static func formattedNumber(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    static func formattedDuration(_ interval: TimeInterval, style: DateComponentsFormatter.UnitsStyle, fallback: String = "–") -> String {
        guard interval > 0 else { return fallback }
        durationFormatter.unitsStyle = style
        durationFormatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        return durationFormatter.string(from: interval) ?? fallback
    }
}

private struct CopySystemInfoButton: View {
    @State private var isCopied: Bool = false
    
    var body: some View {
        Button(action: {
            copySystemInfo()
        }) {
            HStack(spacing: 8) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .rotationEffect(.degrees(isCopied ? 360 : 0))
                
                Text(isCopied ? "Copied!" : "Copy System Info")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .scaleEffect(isCopied ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
    }
    
    private func copySystemInfo() {
        SystemInfoService.shared.copySystemInfoToClipboard()
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
}
