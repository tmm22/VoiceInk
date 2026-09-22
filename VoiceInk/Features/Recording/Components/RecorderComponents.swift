import SwiftUI

// MARK: - Live Transcript View

struct LiveTranscriptView: View {
    /// Leaf observer: only this view re-renders when a streaming partial arrives.
    @ObservedObject var liveTranscript: LiveTranscriptState

    private var text: String { liveTranscript.text }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .id("bottom")
            }
            .frame(height: 56)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .transaction { $0.disablesAnimations = true }
    }
}

// MARK: - Recorder Status Display

struct RecorderStatusDisplay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let currentState: RecordingState
    /// Held as a plain reference; only `RecorderMeterVisualizer` observes it, so meter updates do not
    /// invalidate this view or its parents.
    let recorder: Recorder
    let menuBarHeight: CGFloat?

    init(
        currentState: RecordingState,
        recorder: Recorder,
        menuBarHeight: CGFloat? = nil
    ) {
        self.currentState = currentState
        self.recorder = recorder
        self.menuBarHeight = menuBarHeight
    }

    var body: some View {
        Group {
            if currentState == .enhancing {
                ProcessingStatusDisplay(mode: .enhancing, color: .white).transition(.opacity)
            } else if currentState == .transcribing {
                ProcessingStatusDisplay(mode: .transcribing, color: .white).transition(.opacity)
            } else if currentState == .recording {
                RecorderMeterVisualizer(recorder: recorder, color: .white)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            } else {
                StaticVisualizer(color: .white)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentState)
    }
}

// MARK: - Assistant Response Panel

struct AssistantPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: AssistantSession
    /// Streaming follow-up preview shown in the empty draft field; `nil` hides it.
    let liveFollowUpText: LiveTranscriptState?
    let onSend: (String) -> Void

    @State private var draftMessage = ""
    @FocusState private var isFollowUpFieldFocused: Bool

    private let horizontalPadding: CGFloat = 20
    private let followUpTextColor = Color.white.opacity(0.9)

    private var statusText: String? {
        switch session.phase {
        case .responding, .sendingFollowUp:
            return String(localized: "Thinking")
        case .failed(let message):
            return message
        case .inactive, .ready:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            messageList
            followUpRow
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        .frame(height: 320)
        .onAppear(perform: focusFollowUpFieldIfAvailable)
        .onChange(of: session.phase) {
            focusFollowUpFieldIfAvailable()
        }
    }

    private var fullConversationText: String {
        session.messages.map { msg in
            let prefix = msg.role == .user ? "You" : "Assistant"
            return "\(prefix): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(session.messages) { message in
                        AssistantMessageBubble(message: message)
                            .id(message.id)
                    }

                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.62))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("status")
                    }
                }
                .padding(.vertical, 2)
                .overlay(alignment: .topLeading) {
                    if !session.messages.isEmpty {
                        CopyIconButton(textToCopy: fullConversationText)
                            .scaleEffect(0.72)
                    }
                }
            }
            .onChange(of: session.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: session.phase) {
                scrollToBottom(proxy)
            }
        }
    }

    private var followUpRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if draftMessage.isEmpty, let liveFollowUpText {
                    LiveFollowUpTextLabel(liveTranscript: liveFollowUpText, color: followUpTextColor)
                }

                TextField("", text: $draftMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(followUpTextColor)
                    .tint(followUpTextColor)
                    .disabled(!session.canSendFollowUp)
                    .focused($isFollowUpFieldFocused)
                    .onSubmit(sendDraftMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: sendDraftMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canSendDraft ? .black : .white.opacity(0.35))
                    .frame(width: 24, height: 24)
                    .background(canSendDraft ? Color.white.opacity(0.88) : Color.white.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSendDraft)
            .help("Send follow up")
        }
    }

    private var canSendDraft: Bool {
        session.canSendFollowUp && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraftMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard session.canSendFollowUp, !trimmed.isEmpty else { return }
        draftMessage = ""
        onSend(trimmed)
        focusFollowUpFieldIfAvailable()
    }

    private func focusFollowUpFieldIfAvailable() {
        guard session.canSendFollowUp else { return }
        DispatchQueue.main.async {
            isFollowUpFieldFocused = true
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                if let last = session.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else {
                    proxy.scrollTo("status", anchor: .bottom)
                }
            }
        }
    }
}

private struct AssistantMessageBubble: View {
    let message: AssistantDisplayMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 36)
            }

            MarkdownContentView(
                message.content,
                fontSize: 12,
                foregroundColor: .white.opacity(isUser ? 0.92 : 0.86),
                alignment: .leading
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isUser ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if !isUser {
                    CopyIconButton(textToCopy: message.content)
                        .scaleEffect(0.72)
                        .padding(0)
                }
            }
            .help(isUser ? message.content : "")

            if !isUser {
                Spacer(minLength: 36)
            }
        }
    }
}

/// Leaf observer for the assistant follow-up preview so partials do not re-render the whole panel.
private struct LiveFollowUpTextLabel: View {
    @ObservedObject var liveTranscript: LiveTranscriptState
    let color: Color

    var body: some View {
        if !liveTranscript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(liveTranscript.text)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.head)
                .allowsHitTesting(false)
        }
    }
}
