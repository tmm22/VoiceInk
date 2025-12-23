import SwiftUI

extension ConfigurationView {
    @ViewBuilder
    var aiEnhancementSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: Localization.PowerMode.aiEnhancementSectionTitle)

            Toggle(Localization.PowerMode.enableAIEnhancementLabel, isOn: $isAIEnhancementEnabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: isAIEnhancementEnabled) { oldValue, newValue in
                    if newValue {
                        if selectedAIProvider == nil {
                            selectedAIProvider = aiService.selectedProvider.rawValue
                        }
                        if selectedAIModel == nil {
                            selectedAIModel = aiService.currentModel
                        }
                    }
                }

            Divider()

            if isAIEnhancementEnabled {
                aiProviderSelection
                aiModelSelection
                promptSelectionSection

                Divider()

                Toggle(Localization.PowerMode.contextAwarenessLabel, isOn: $useScreenCapture)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var aiProviderSelection: some View {
        let providerBinding = Binding<AIProvider>(
            get: {
                if let providerName = selectedAIProvider,
                   let provider = AIProvider(rawValue: providerName) {
                    return provider
                }
                return aiService.selectedProvider
            },
            set: { newValue in
                selectedAIProvider = newValue.rawValue
                aiService.selectedProvider = newValue
                selectedAIModel = nil
            }
        )

        HStack {
            Text(Localization.PowerMode.aiProviderLabel)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if aiService.connectedProviders.isEmpty {
                Text(Localization.PowerMode.noProvidersConnected)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("", selection: providerBinding) {
                    ForEach(aiService.connectedProviders.filter { $0 != .elevenLabs && $0 != .deepgram }, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .labelsHidden()
                .onChange(of: selectedAIProvider) { oldValue, newValue in
                    if let provider = newValue.flatMap({ AIProvider(rawValue: $0) }) {
                        selectedAIModel = provider.defaultModel
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var aiModelSelection: some View {
        let providerName = selectedAIProvider ?? aiService.selectedProvider.rawValue
        if let provider = AIProvider(rawValue: providerName),
           provider != .custom {

            HStack {
                Text(Localization.PowerMode.aiModelLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if aiService.availableModels.isEmpty {
                    Text(provider == .openRouter ? Localization.PowerMode.noModelsLoaded : Localization.PowerMode.noModelsAvailable)
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let modelBinding = Binding<String>(
                        get: {
                            if let model = selectedAIModel, !model.isEmpty {
                                return model
                            }
                            return aiService.currentModel
                        },
                        set: { newModelValue in
                            selectedAIModel = newModelValue
                            aiService.selectModel(newModelValue)
                        }
                    )

                    let models = provider == .openRouter ? aiService.availableModels : (provider == .ollama ? aiService.availableModels : provider.availableModels)

                    Picker("", selection: modelBinding) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()

                    if provider == .openRouter {
                        Button(action: {
                            Task {
                                await aiService.fetchOpenRouterModels()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(Localization.PowerMode.refreshModelsHelp)
                    }

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var promptSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Localization.PowerMode.enhancementPromptLabel)
                .font(.headline)
                .foregroundColor(.primary)

            PromptSelectionGrid(
                prompts: enhancementService.allPrompts,
                selectedPromptId: selectedPromptId,
                onPromptSelected: { prompt in
                    selectedPromptId = prompt.id
                },
                onEditPrompt: { prompt in
                    selectedPromptForEdit = prompt
                },
                onDeletePrompt: { prompt in
                    enhancementService.deletePrompt(prompt)
                },
                onAddNewPrompt: {
                    isEditingPrompt = true
                }
            )
        }
    }
}
