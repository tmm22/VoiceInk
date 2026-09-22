import SwiftUI

// MARK: - Icon Toggle Button

struct RecorderToggleButton: View {
    let isEnabled: Bool
    let icon: String
    let disabled: Bool
    let action: () -> Void

    init(isEnabled: Bool, icon: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.icon = icon
        self.disabled = disabled
        self.action = action
    }

    private var isEmoji: Bool {
        !icon.contains(".") && !icon.contains("-") && icon.unicodeScalars.contains { !$0.isASCII }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isEmoji {
                    Text(icon).font(.system(size: 14))
                } else {
                    Image(systemName: icon).font(.system(size: 13))
                }
            }
            .foregroundColor(disabled ? .white.opacity(0.3) : (isEnabled ? .white : .white.opacity(0.6)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
    }
}

// MARK: - Record Button

struct RecorderRecordButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recordingState: RecordingState
    let action: () -> Void

    private var visualState: VisualState {
        switch recordingState {
        case .idle, .starting, .busy:
            return .ready
        case .recording:
            return .recording
        case .transcribing, .enhancing:
            return .processing
        }
    }

    private var isDisabled: Bool {
        switch recordingState {
        case .idle, .recording:
            return false
        case .starting, .transcribing, .enhancing, .busy:
            return true
        }
    }

    var body: some View {
        Button(action: action) {
            buttonFace
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(accessibilityLabel)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var buttonFace: some View {
        ZStack {
            Circle()
                .fill(colors.surface)
                .overlay(
                    Circle()
                        .strokeBorder(colors.border, lineWidth: 0.6)
                )

            stateMark
        }
        .frame(width: 21, height: 21)
        .contentShape(Circle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: visualState)
    }

    private var colors: StateColors {
        switch visualState {
        case .ready:
            return StateColors(
                surface: Color(red: 0.30, green: 0.30, blue: 0.32),
                border: Color(red: 0.42, green: 0.42, blue: 0.44),
                mark: Color(red: 0.78, green: 0.78, blue: 0.80)
            )
        case .recording:
            let red = AppTheme.Status.error
            return StateColors(
                surface: red.opacity(0.92),
                border: red.opacity(0.98),
                mark: .white
            )
        case .processing:
            return StateColors(
                surface: Color.white.opacity(0.13),
                border: Color.white.opacity(0.18),
                mark: Color.white.opacity(0.86)
            )
        }
    }

    @ViewBuilder
    private var stateMark: some View {
        switch visualState {
        case .ready, .recording:
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .fill(colors.mark)
                .frame(width: 8, height: 8)
        case .processing:
            ProcessingIndicator(color: colors.mark)
        }
    }

    private var accessibilityLabel: String {
        switch recordingState {
        case .idle:
            return String(localized: "Start recording")
        case .starting:
            return String(localized: "Starting recording")
        case .recording:
            return String(localized: "Stop recording")
        case .transcribing:
            return String(localized: "Transcribing recording")
        case .enhancing:
            return String(localized: "Enhancing recording")
        case .busy:
            return String(localized: "Recorder unavailable")
        }
    }

    private enum VisualState: Equatable {
        case ready
        case recording
        case processing
    }

    private struct StateColors {
        let surface: Color
        let border: Color
        let mark: Color
    }
}

// MARK: - Close Button

struct RecorderCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.13))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    )

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.86))
            }
            .frame(width: 21, height: 21)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
        .accessibilityLabel(Text("Close"))
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: 1.5)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
            .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: rotation)
            .onAppear { rotation = reduceMotion ? 0 : 360 }
            .onChange(of: reduceMotion) { _, reduced in rotation = reduced ? 0 : 360 }
            .accessibilityHidden(true)
    }
}

// MARK: - Progress Dot Animation

struct ProgressAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let animationSpeed: Double

    private let dotCount = 5
    private let dotSize: CGFloat = 3
    private let dotSpacing: CGFloat = 2

    @State private var currentDot = 0
    @State private var timer: Timer?

    init(color: Color = .white, animationSpeed: Double = 0.3) {
        self.color = color
        self.animationSpeed = animationSpeed
    }

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: dotSize / 2)
                    .fill(color.opacity(index <= currentDot ? 0.85 : 0.25))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .accessibilityHidden(true)
        .onAppear { startAnimation() }
        .onChange(of: reduceMotion) { _, _ in startAnimation() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startAnimation() {
        timer?.invalidate()
        timer = nil
        currentDot = 0
        guard !reduceMotion else { return }
        timer = Timer.scheduledTimer(withTimeInterval: animationSpeed, repeats: true) { _ in
            currentDot = (currentDot + 1) % (dotCount + 2)
            if currentDot > dotCount { currentDot = -1 }
        }
    }
}

// MARK: - Mode Button

struct RecorderModeButton: View {
    @ObservedObject private var modeManager = ModeManager.shared
    let buttonSize: CGFloat
    let padding: EdgeInsets

    @State private var isPopoverPresented = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var dismissWorkItem: DispatchWorkItem?

    init(buttonSize: CGFloat = 28, padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 7)) {
        self.buttonSize = buttonSize
        self.padding = padding
    }

    var body: some View {
        RecorderToggleButton(
            isEnabled: !modeManager.enabledConfigurations.isEmpty,
            icon: modeManager.enabledConfigurations.isEmpty
                ? "square.grid.2x2" : (modeManager.currentEffectiveConfiguration?.icon.value ?? "square.grid.2x2"),
            disabled: modeManager.enabledConfigurations.isEmpty
        ) {
            isPopoverPresented.toggle()
        }
        .accessibilityLabel(Text("Recording mode"))
        .frame(width: buttonSize)
        .padding(padding)
        .onHover {
            isHoveringButton = $0
            syncPopoverVisibility()
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            ModePopover()
                .onHover {
                    isHoveringPopover = $0
                    syncPopoverVisibility()
                }
        }
    }

    private func syncPopoverVisibility() {
        if isHoveringButton || isHoveringPopover {
            dismissWorkItem?.cancel()
            dismissWorkItem = nil
            isPopoverPresented = true
        } else {
            dismissWorkItem?.cancel()
            let work = DispatchWorkItem { [isPopoverPresentedBinding = $isPopoverPresented] in
                isPopoverPresentedBinding.wrappedValue = false
            }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

