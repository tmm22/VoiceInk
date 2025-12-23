import SwiftUI

struct EmojiPickerView: View {
    @StateObject private var emojiManager = EmojiManager.shared
    @Binding var selectedEmoji: String
    @Binding var isPresented: Bool
    @State private var newEmojiText: String = ""
    @State private var isAddingCustomEmoji: Bool = false
    @FocusState private var isEmojiTextFieldFocused: Bool
    @State private var inputFeedbackMessage: String = ""
    @State private var inputFeedbackIsError: Bool = false
    @State private var showingEmojiInUseAlert = false
    @State private var emojiForAlert: String? = nil
    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(emojiManager.allEmojis, id: \.self) { emoji in
                        EmojiButton(
                            emoji: emoji,
                            isSelected: selectedEmoji == emoji,
                            isCustom: emojiManager.isCustomEmoji(emoji),
                            removeAction: {
                                attemptToRemoveCustomEmoji(emoji)
                            }
                        ) {
                            selectedEmoji = emoji
                            inputFeedbackMessage = ""
                            inputFeedbackIsError = false
                            isPresented = false
                        }
                    }

                    AddEmojiButton {
                        isAddingCustomEmoji.toggle()
                        newEmojiText = ""
                        inputFeedbackMessage = ""
                        inputFeedbackIsError = false
                        if isAddingCustomEmoji {
                            Task { @MainActor in
                                // Best-effort delay to let the field appear.
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                isEmojiTextFieldFocused = true
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 200)

            if isAddingCustomEmoji {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("➕", text: $newEmojiText)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 70)
                            .focused($isEmojiTextFieldFocused)
                            .onChange(of: newEmojiText) { _, newValue in
                                inputFeedbackMessage = ""
                                let cleaned = newValue.firstValidEmojiCharacter()
                                if newEmojiText != cleaned {
                                    newEmojiText = cleaned
                                }
                                if !newEmojiText.isEmpty && emojiManager.allEmojis.contains(newEmojiText) {
                                    inputFeedbackMessage = Localization.PowerMode.emojiAlreadyExists
                                    inputFeedbackIsError = true
                                } else if !newEmojiText.isEmpty && !newEmojiText.isValidEmoji {
                                    inputFeedbackMessage = Localization.PowerMode.emojiInvalid
                                    inputFeedbackIsError = true
                                } else {
                                    inputFeedbackMessage = ""
                                    inputFeedbackIsError = false
                                }
                            }
                            .onSubmit(attemptAddCustomEmoji)

                        Button(Localization.PowerMode.addButton) {
                            attemptAddCustomEmoji()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newEmojiText.isEmpty || !newEmojiText.isValidEmoji || emojiManager.allEmojis.contains(newEmojiText))

                        Button(Localization.PowerMode.cancelButton) {
                            isAddingCustomEmoji = false
                            newEmojiText = ""
                            inputFeedbackMessage = ""
                            inputFeedbackIsError = false
                        }
                        .buttonStyle(.bordered)
                    }
                    if !inputFeedbackMessage.isEmpty {
                        Text(inputFeedbackMessage)
                            .font(.caption)
                            .foregroundColor(inputFeedbackIsError ? .red : .secondary)
                            .transition(.opacity)
                    }
                    Text(Localization.PowerMode.emojiTip)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.horizontal)
                .padding(.bottom, 5)
            }
        }
        .padding()
        .background(.regularMaterial)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 320, minHeight: 150, idealHeight: 280, maxHeight: 350)
        .alert(Localization.PowerMode.emojiInUseTitle, isPresented: $showingEmojiInUseAlert, presenting: emojiForAlert) { _ in
            Button(Localization.PowerMode.okButton, role: .cancel) { }
        } message: { emojiStr in
            Text(String(format: Localization.PowerMode.emojiInUseMessage, emojiStr))
        }
    }

    private func attemptAddCustomEmoji() {
        let trimmedEmoji = newEmojiText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmoji.isEmpty else {
            inputFeedbackMessage = Localization.PowerMode.emojiEmpty
            inputFeedbackIsError = true
            return
        }
        guard trimmedEmoji.isValidEmoji else {
            inputFeedbackMessage = Localization.PowerMode.emojiInvalidCharacter
            inputFeedbackIsError = true
            return
        }
        guard !emojiManager.allEmojis.contains(trimmedEmoji) else {
            inputFeedbackMessage = Localization.PowerMode.emojiAlreadyExists
            inputFeedbackIsError = true
            return
        }

        if emojiManager.addCustomEmoji(trimmedEmoji) {
            selectedEmoji = trimmedEmoji
            inputFeedbackMessage = ""
            inputFeedbackIsError = false
            isAddingCustomEmoji = false
            newEmojiText = ""
        } else {
            inputFeedbackMessage = Localization.PowerMode.emojiAddFailed
            inputFeedbackIsError = true
        }
    }

    private func attemptToRemoveCustomEmoji(_ emojiToRemove: String) {
        guard emojiManager.isCustomEmoji(emojiToRemove) else { return }

        if PowerModeManager.shared.isEmojiInUse(emojiToRemove) {
            emojiForAlert = emojiToRemove
            showingEmojiInUseAlert = true
        } else {
            if emojiManager.removeCustomEmoji(emojiToRemove) {
                if selectedEmoji == emojiToRemove {
                    selectedEmoji = emojiManager.allEmojis.first ?? selectedEmoji
                }
            }
        }
    }
}

private struct EmojiButton: View {
    let emoji: String
    let isSelected: Bool
    let isCustom: Bool
    let removeAction: () -> Void
    let selectAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: selectAction) {
                Text(emoji)
                    .font(.largeTitle) 
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                    )
                    .overlay( 
                        Circle()
                            .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            }
            .buttonStyle(.plain) 

            if isCustom {
                Button(action: removeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.red)
                        .font(.caption2)
                        .background(Circle().fill(Color.white.opacity(0.8)))
                }
                .buttonStyle(.borderless) 
                .offset(x: 6, y: -6)
            }
        }
    }
}

private struct AddEmojiButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(Localization.PowerMode.addEmojiLabel, systemImage: "plus.circle.fill")
                .font(.title2)
                .labelStyle(.iconOnly)
                .foregroundColor(.accentColor)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(Localization.PowerMode.addCustomEmojiHelp)
    }
}

extension String {
    var isValidEmoji: Bool {
        guard !self.isEmpty else { return false }
        return self.count == 1 && self.unicodeScalars.first?.properties.isEmoji ?? false
    }

    func firstValidEmojiCharacter() -> String {
        return self.filter { $0.unicodeScalars.allSatisfy { $0.properties.isEmoji } }.prefix(1).map(String.init).joined()
    }
}

#if DEBUG
struct EmojiPickerView_Previews: PreviewProvider {
    static var previews: some View {
        EmojiPickerView(
            selectedEmoji: .constant("😀"),
            isPresented: .constant(true)
        )
        .environmentObject(EmojiManager.shared)
    }
}
#endif

 
