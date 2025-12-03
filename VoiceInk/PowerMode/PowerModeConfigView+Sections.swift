import SwiftUI

// MARK: - Configuration View Sections

extension ConfigurationView {
    
    // MARK: - Header Section
    
    @ViewBuilder
    var headerSection: some View {
        HStack {
            Text(mode.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer()
            
            if case .edit(let config) = mode {
                Button("Delete") {
                    let alert = NSAlert()
                    alert.messageText = "Delete Power Mode?"
                    alert.informativeText = "Are you sure you want to delete the '\(config.name)' power mode? This action cannot be undone."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Delete")
                    alert.addButton(withTitle: "Cancel")
                    
                    // Style the Delete button as destructive
                    alert.buttons[0].hasDestructiveAction = true
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        powerModeManager.removeConfiguration(with: config.id)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .foregroundColor(.red)
                .padding(.trailing, 8)
            }
            
            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 10)
    }
    
    // MARK: - Main Input Section
    
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
                
                TextField("Name your power mode", text: $configName)
                    .font(.system(size: 18, weight: .bold))
                    .textFieldStyle(.plain)
                    .foregroundColor(.primary)
                    .tint(.accentColor)
                    .focused($isNameFieldFocused)
            }
            
            // Default Power Mode Toggle
            HStack {
                Toggle("Set as default power mode", isOn: $isDefault)
                    .font(.system(size: 14))
                
                InfoTip(
                    title: "Default Power Mode",
                    message: "Default power mode is used when no specific app or website matches are found"
                )
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(CardBackground(isSelected: false))
        .padding(.horizontal)
    }
    
    // MARK: - Trigger Section
    
    @ViewBuilder
    var triggerSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "When to Trigger")
            
            // Applications subsection
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Applications")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        loadInstalledApps()
                        isShowingAppPicker = true
                    }) {
                        Label("Add App", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
                
                if selectedAppConfigs.isEmpty {
                    HStack {
                        Spacer()
                        Text("No applications added")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding()
                    .background(CardBackground(isSelected: false))
                } else {
                    // Grid of selected apps that wraps to next line
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50, maximum: 55), spacing: 10)], spacing: 10) {
                        ForEach(selectedAppConfigs) { appConfig in
                            appConfigItem(appConfig)
                        }
                    }
                }
            }
            
            Divider()
            
            // Websites subsection
            VStack(alignment: .leading, spacing: 12) {
                Text("Websites")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    
                // Add URL Field
                HStack {
                    TextField("Enter website URL (e.g., google.com)", text: $newWebsiteURL)
                    .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWebsite()
                        }
                    
                    Button(action: addWebsite) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(newWebsiteURL.isEmpty)
                }
                
                if websiteConfigs.isEmpty {
                    HStack {
                        Spacer()
                        Text("No websites added")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding()
                    .background(CardBackground(isSelected: false))
                } else {
                    // Grid of website tags that wraps to next line
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 10)], spacing: 10) {
                        ForEach(websiteConfigs) { urlConfig in
                            websiteConfigItem(urlConfig)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func appConfigItem(_ appConfig: AppConfig) -> some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                // App icon - completely filling the container
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appConfig.bundleIdentifier) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                // Remove button
                Button(action: {
                    selectedAppConfigs.removeAll(where: { $0.id == appConfig.id })
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .frame(width: 50, height: 50)
        .background(CardBackground(isSelected: false, cornerRadius: 10))
    }
    
    @ViewBuilder
    private func websiteConfigItem(_ urlConfig: URLConfig) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            
            Text(urlConfig.url)
                .font(.system(size: 11))
                .lineLimit(1)
            
            Spacer(minLength: 0)
            
            Button(action: {
                websiteConfigs.removeAll(where: { $0.id == urlConfig.id })
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 28)
        .background(CardBackground(isSelected: false, cornerRadius: 10))
    }
    
    // MARK: - Transcription Section
    
    @ViewBuilder
    var transcriptionSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Transcription")
            
            if whisperState.usableModels.isEmpty {
                Text("No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab.")
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
                    Text("Model")
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
                Text("Language")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Autodetected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        } else if let selectedModel = effectiveModelName,
                  let modelInfo = whisperState.allAvailableModels.first(where: { $0.name == selectedModel }),
                  modelInfo.isMultilingualModel {
            
            let languageBinding = Binding<String?>(
                get: {
                    selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
                },
                set: { selectedLanguage = $0 }
            )
            
            HStack {
                Text("Language")
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
    
    // MARK: - AI Enhancement Section
    
    @ViewBuilder
    var aiEnhancementSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "AI Enhancement")

            Toggle("Enable AI Enhancement", isOn: $isAIEnhancementEnabled)
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
                
                Toggle("Context Awareness", isOn: $useScreenCapture)
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
            Text("AI Provider")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if aiService.connectedProviders.isEmpty {
                Text("No providers connected")
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
                Text("AI Model")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if aiService.availableModels.isEmpty {
                    Text(provider == .openRouter ? "No models loaded" : "No models available")
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
                        .help("Refresh models")
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    @ViewBuilder
    private var promptSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enhancement Prompt")
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
    
    // MARK: - Advanced Section
    
    @ViewBuilder
    var advancedSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Advanced")

            HStack {
                Toggle("Auto Send", isOn: $isAutoSendEnabled)
                
                InfoTip(
                    title: "Auto Send",
                    message: "Automatically presses the Return/Enter key after pasting text. This is useful for chat applications or forms where its not necessary to to make changes to the transcribed text"
                )
                
                Spacer()
            }
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .padding(.horizontal)
    }
    
    // MARK: - Save Button
    
    @ViewBuilder
    var saveButtonSection: some View {
        HStack {
            Spacer()
            Button(action: saveConfiguration) {
                Text(mode.isAdding ? "Add New Power Mode" : "Save Changes")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canSave ? Color(red: 0.3, green: 0.7, blue: 0.4) : Color(red: 0.3, green: 0.7, blue: 0.4).opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal)
    }
}