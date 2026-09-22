import SwiftUI

struct AudioVisualizer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let audioMeter: AudioMeter
    let color: Color
    let isActive: Bool

    private static let barCount = 15
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2
    private static let minHeight: CGFloat = 4
    private static let maxHeight: CGFloat = 28
    private static let frameInterval = 1.0 / 30.0

    /// Per-bar sine phase and centre emphasis; depend only on the bar index.
    private static let phases: [Double] = (0..<barCount).map { Double($0) * 0.4 }
    private static let centerBoosts: [Double] = (0..<barCount).map { index in
        let centerDistance = abs(Double(index) - Double(barCount) / 2) / Double(barCount / 2)
        return 1.0 - (centerDistance * 0.4)
    }

    init(audioMeter: AudioMeter, color: Color, isActive: Bool) {
        self.audioMeter = audioMeter
        self.color = color
        self.isActive = isActive
    }

    /// Boosted for visibility; computed once per meter value rather than once per bar per frame.
    private var amplitude: Double {
        guard isActive else { return 0 }
        return max(0, min(1, pow(audioMeter.averagePower, 0.7)))
    }

    var body: some View {
        let amplitude = amplitude
        let fill = color.opacity(0.85)

        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !isActive || amplitude == 0 || reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSince1970

            HStack(spacing: Self.barSpacing) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: Self.barWidth / 2)
                        .fill(fill)
                        .frame(
                            width: Self.barWidth,
                            height: Self.barHeight(for: index, time: time, amplitude: amplitude)
                        )
                }
            }
        }
    }

    private static func barHeight(for index: Int, time: TimeInterval, amplitude: Double) -> CGFloat {
        guard amplitude > 0 else { return minHeight }

        let wave = sin(time * 8 + phases[index]) * 0.5 + 0.5
        return max(minHeight, minHeight + CGFloat(amplitude * wave * centerBoosts[index]) * (maxHeight - minHeight))
    }
}

/// Leaf view that observes the recorder so meter updates invalidate only the visualiser, not the
/// surrounding recorder chrome.
struct RecorderMeterVisualizer: View {
    @ObservedObject var recorder: Recorder
    let color: Color

    var body: some View {
        AudioVisualizer(audioMeter: recorder.audioMeter, color: color, isActive: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Recording"))
    }
}

// Flat bars shown when the recorder is idle (no audio input)
struct StaticVisualizer: View {
    private let barCount = 15
    private let barWidth: CGFloat = 3
    private let barHeight: CGFloat = 4
    private let barSpacing: CGFloat = 2
    let color: Color

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color.opacity(0.5))
                    .frame(width: barWidth, height: barHeight)
            }
        }
        // Flat placeholder bars convey nothing to assistive technology.
        .accessibilityHidden(true)
    }
}

// MARK: - Processing Status Display

struct ProcessingStatusDisplay: View {
    enum Mode {
        case transcribing
        case enhancing
    }

    let mode: Mode
    let color: Color

    private var label: LocalizedStringKey {
        switch mode {
        case .transcribing: return "Transcribing"
        case .enhancing: return "Enhancing"
        }
    }

    private var animationSpeed: Double {
        switch mode {
        case .transcribing: return 0.18
        case .enhancing: return 0.22
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .foregroundColor(color)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            ProgressAnimation(color: color, animationSpeed: animationSpeed)
        }
        .frame(height: 28)  // matches AudioVisualizer maxHeight to prevent layout shift
    }
}
