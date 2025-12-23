import SwiftUI

struct TTSSettingsView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var playback: TTSPlaybackViewModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - API Key State
    @State var elevenLabsKey: String = ""
    @State var openAIKey: String = ""
    @State var googleKey: String = ""
    
    @State var showElevenLabsKey = false
    @State var showOpenAIKey = false
    @State var showGoogleKey = false

    @State private var saveMessage: String?
    @State private var showingSaveAlert = false

    @State private var selectedTab = "api"

    // MARK: - Managed Provisioning State
    @State var managedBaseURL: String = ""
    @State var managedAccountId: String = ""
    @State var managedPlanTier: String = ""
    @State var managedPlanStatus: String = ""
    @State var managedProvisioningEnabledToggle: Bool = false
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Divider()
            
            tabPicker
            
            // Content based on selected tab
            ScrollView {
                switch selectedTab {
                case "api":
                    apiKeysSection()
                case "audio":
                    audioSettingsSection()
                case "general":
                    generalSettingsSection()
                case "about":
                    TTSAboutView()
                default:
                    EmptyView()
                }
            }
            
            Divider()
            
            footerButtons
        }
        .frame(width: 600, height: 500)
        .onAppear {
            loadAPIKeys()
            loadManagedProvisioning()
        }
        .onChange(of: settings.managedProvisioningConfiguration) {
            loadManagedProvisioning()
        }
        .onChange(of: settings.managedProvisioningEnabled) {
            loadManagedProvisioning()
        }
        .alert("Settings Saved", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveMessage ?? "Your settings have been saved successfully.")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Tab Picker
    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Label("API Keys", systemImage: "key.fill").tag("api")
            Label("Audio", systemImage: "speaker.wave.2.fill").tag("audio")
            Label("General", systemImage: "gear").tag("general")
            Label("About", systemImage: "info.circle.fill").tag("about")
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
    }
    
    // MARK: - Footer Buttons
    private var footerButtons: some View {
        HStack {
            Button("Reset to Defaults") {
                resetToDefaults()
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)
            
            Button("Save") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    func loadAPIKeys() {
        elevenLabsKey = settings.getAPIKey(for: .elevenLabs) ?? ""
        openAIKey = settings.getAPIKey(for: .openAI) ?? ""
        googleKey = settings.getAPIKey(for: .google) ?? ""
    }

    func loadManagedProvisioning() {
        if let config = settings.managedProvisioningConfiguration {
            managedBaseURL = config.baseURL.absoluteString
            managedAccountId = config.accountId
            managedPlanTier = config.planTier
            managedPlanStatus = config.planStatus
        } else {
            managedBaseURL = ""
            managedAccountId = ""
            managedPlanTier = ""
            managedPlanStatus = ""
        }
        managedProvisioningEnabledToggle = settings.managedProvisioningEnabled
    }
    
    private func saveSettings() {
        // Validate and save API keys
        if !elevenLabsKey.isEmpty {
            if KeychainManager.isValidAPIKey(elevenLabsKey, for: "ElevenLabs") {
                settings.saveAPIKey(elevenLabsKey, for: .elevenLabs)
            } else {
                saveMessage = "Invalid ElevenLabs API key format. Please check and try again."
                showingSaveAlert = true
                return
            }
        }
        if !openAIKey.isEmpty {
            if KeychainManager.isValidAPIKey(openAIKey, for: "OpenAI") {
                settings.saveAPIKey(openAIKey, for: .openAI)
            } else {
                saveMessage = "Invalid OpenAI API key format. Keys should start with 'sk-'."
                showingSaveAlert = true
                return
            }
        }
        if !googleKey.isEmpty {
            if KeychainManager.isValidAPIKey(googleKey, for: "Google") {
                settings.saveAPIKey(googleKey, for: .google)
            } else {
                saveMessage = "Invalid Google Cloud API key format. Please check and try again."
                showingSaveAlert = true
                return
            }
        }

        // Save other settings
        settings.saveSettings()

        // Validate and save managed provisioning configuration
        let trimmedURL = managedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = managedAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedURL.isEmpty || trimmedAccount.isEmpty {
            settings.clearManagedProvisioning()
        } else {
            // Validate HTTPS for managed provisioning
            guard let url = URL(string: trimmedURL), url.scheme?.lowercased() == "https" else {
                saveMessage = "Managed provisioning base URL must use HTTPS for security."
                showingSaveAlert = true
                return
            }
            
            settings.updateManagedProvisioningConfiguration(
                baseURL: trimmedURL,
                accountId: trimmedAccount,
                planTier: managedPlanTier.isEmpty ? "free" : managedPlanTier,
                planStatus: managedPlanStatus.isEmpty ? "free" : managedPlanStatus,
                enabled: managedProvisioningEnabledToggle
            )
        }
        loadManagedProvisioning()

        saveMessage = "All settings have been saved successfully."
        showingSaveAlert = true

        // Dismiss after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
    
    private func resetToDefaults() {
        playback.playbackSpeed = 1.0
        playback.volume = 0.75
        playback.isLoopEnabled = false
        settings.clearManagedProvisioning()
        loadManagedProvisioning()
    }
}

// MARK: - Preview
struct TTSSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = TTSViewModel()
        TTSSettingsView()
            .environmentObject(viewModel.settings)
            .environmentObject(viewModel.playback)
    }
}
