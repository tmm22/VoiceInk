import SwiftUI

extension ConfigurationView {
    @ViewBuilder
    var transcriptionSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: Localization.PowerMode.transcriptionSectionTitle)

            if whisperState.usableModels.isEmpty {
                Text(Localization.PowerMode.noTranscriptionModels)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(CardBackground(isSelected: false))
            } else {
                let modelBinding = Binding<String?>(
                    get: {
                        selectedTranscriptionModelName ?? whisperState.usableModels.first?.name
                    },
                    set: { selectedTranscriptionModelName = $0 }
                )

                HStack {
                    Text(Localization.PowerMode.modelLabel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("", selection: modelBinding) {
                        ForEach(whisperState.usableModels, id: \.name) { model in
                            Text(model.displayName).tag(model.name as String?)
                        }
                    }
                    .labelsHidden()

                    Spacer()
                }
            }

            languageSelectionView
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var languageSelectionView: some View {
        if languageSelectionDisabled() {
            HStack {
                Text(Localization.PowerMode.languageLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(Localization.PowerMode.autodetectedLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
        } else if let selectedModel = effectiveModelName,
                  let modelInfo = whisperState.allAvailableModels.first(where: { $0.name == selectedModel }),
                  modelInfo.isMultilingualModel {

            let languageBinding = Binding<String?>(
                get: {
                    selectedLanguage ?? AppSettings.TranscriptionSettings.selectedLanguage ?? "auto"
                },
                set: { selectedLanguage = $0 }
            )

            HStack {
                Text(Localization.PowerMode.languageLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: languageBinding) {
                    ForEach(modelInfo.supportedLanguages.sorted(by: {
                        if $0.key == "auto" { return true }
                        if $1.key == "auto" { return false }
                        return $0.value < $1.value
                    }), id: \.key) { key, value in
                        Text(value).tag(key as String?)
                    }
                }
                .labelsHidden()

                Spacer()
            }
        } else if let selectedModel = effectiveModelName,
                  let modelInfo = whisperState.allAvailableModels.first(where: { $0.name == selectedModel }),
                  !modelInfo.isMultilingualModel {

            EmptyView()
                .onAppear {
                    if selectedLanguage == nil {
                        selectedLanguage = "en"
                    }
                }
        }
    }
}
