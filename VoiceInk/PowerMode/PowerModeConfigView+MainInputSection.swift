import SwiftUI

extension ConfigurationView {
    @ViewBuilder
    var mainInputSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button(action: {
                    isShowingEmojiPicker.toggle()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 48, height: 48)

                        Text(selectedEmoji)
                            .font(.system(size: 24))
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingEmojiPicker, arrowEdge: .bottom) {
                    EmojiPickerView(
                        selectedEmoji: $selectedEmoji,
                        isPresented: $isShowingEmojiPicker
                    )
                }

                TextField(Localization.PowerMode.namePlaceholder, text: $configName)
                    .font(.system(size: 18, weight: .bold))
                    .textFieldStyle(.plain)
                    .foregroundColor(.primary)
                    .tint(.accentColor)
                    .focused($isNameFieldFocused)
            }

            HStack {
                Toggle(Localization.PowerMode.setAsDefaultLabel, isOn: $isDefault)
                    .font(.system(size: 14))

                InfoTip(
                    title: Localization.PowerMode.defaultPowerModeTitle,
                    message: Localization.PowerMode.defaultPowerModeMessage
                )

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(CardBackground(isSelected: false))
        .padding(.horizontal)
    }
}
