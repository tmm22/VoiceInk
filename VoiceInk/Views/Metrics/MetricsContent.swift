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
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            heroSection
                            metricsSection
                            HelpAndResourcesSection()

                            Spacer(minLength: 20)

                            HStack {
                                Spacer()
                                footerActionsView
                            }
                        }
                        .frame(minHeight: geometry.size.height - 56)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 32)
                    }
                    .background(Color(.windowBackgroundColor))
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
        VStack(spacing: 12) {
            HStack {
                Spacer(minLength: 0)
                
                (Text("You have saved ")
                    .fontWeight(.regular)
                    .foregroundColor(.primary)
                 +
                 Text(formattedTimeSaved)
                    .fontWeight(.semibold)
                    .font(.system(size: 28, design: .default))
                    .foregroundColor(.primary)
                 +
                 Text(" with \(AppBrand.communityName)")
                    .fontWeight(.regular)
                    .foregroundColor(.primary)
                )
                .font(.system(size: 20))
                .multilineTextAlignment(.center)
                
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            
            Text(heroSubtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(CardBackground(isSelected: false))
    }
    
    private var metricsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            MetricCard(
                icon: "mic.fill",
                title: "Sessions Recorded",
                value: "\(transcriptions.count)",
                detail: "\(AppBrand.communityName) sessions completed",
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
                detail: "\(AppBrand.primaryName) vs. typing by hand",
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
            FeedbackButton()
        }
    }
    
    private var formattedTimeSaved: String {
        Formatters.formattedDuration(timeSaved, style: .full, fallback: "Time savings on the way")
    }
    
    private var heroSubtitle: String {
        guard !transcriptions.isEmpty else {
            return "Your \(AppBrand.communityName) journey starts with your first recording."
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

private struct FeedbackButton: View {
    @State private var isClicked: Bool = false

    var body: some View {
        Button(action: {
            openFeedback()
        }) {
            HStack(spacing: 8) {
                Image(systemName: isClicked ? "checkmark.circle.fill" : "exclamationmark.bubble.fill")
                    .rotationEffect(.degrees(isClicked ? 360 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isClicked)

                Text(isClicked ? "Sending" : "Feedback or Issues?")
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isClicked)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .scaleEffect(isClicked ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isClicked)
    }

    private func openFeedback() {
        EmailSupport.openSupportEmail()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isClicked = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isClicked = false
            }
        }
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
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)

                Text(isCopied ? "Copied!" : "Copy System Info")
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
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

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCopied = false
            }
        }
    }
}
