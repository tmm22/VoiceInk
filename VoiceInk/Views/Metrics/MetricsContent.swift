import SwiftUI

struct MetricsContent: View {
    let transcriptions: [Transcription]
    
    var body: some View {
        if transcriptions.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    TimeEfficiencyView(totalRecordedTime: totalRecordedTime, estimatedTypingTime: estimatedTypingTime)

                    metricsGrid
                }
                .padding()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No Transcriptions Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Start recording to see your metrics")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
    
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            MetricCard(
                title: "Words Dictated",
                value: "\(totalWordsTranscribed)",
                icon: "text.word.spacing",
                color: .blue
            )
            MetricCard(
                title: "VoiceInk Sessions",
                value: "\(transcriptions.count)",
                icon: "mic.circle.fill",
                color: .green
            )
            MetricCard(
                title: "Average Words/Minute",
                value: String(format: "%.1f", averageWordsPerMinute),
                icon: "speedometer",
                color: .orange
            )
            MetricCard(
                title: "Words/Session",
                value: String(format: "%.1f", averageWordsPerSession),
                icon: "chart.bar.fill",
                color: .purple
            )
        }
    }
    
    
    // Computed properties for metrics
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
    
    
    // Add computed properties for new metrics
    private var averageWordsPerMinute: Double {
        guard totalRecordedTime > 0 else { return 0 }
        return Double(totalWordsTranscribed) / (totalRecordedTime / 60.0)
    }
    
    private var averageWordsPerSession: Double {
        guard !transcriptions.isEmpty else { return 0 }
        return Double(totalWordsTranscribed) / Double(transcriptions.count)
    }
} 
