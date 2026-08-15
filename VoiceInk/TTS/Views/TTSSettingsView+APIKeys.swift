import SwiftUI

// MARK: - API Keys Section
extension TTSSettingsView {
    @ViewBuilder
    func apiKeysSection() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Localization.TTS.apiKeys)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(Localization.TTS.keychainStorageDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // ElevenLabs
            elevenLabsKeySection()
            
            // OpenAI
            openAIKeySection()
            
            // Google Cloud
            googleKeySection()
            
            // Managed Provisioning
            managedProvisioningSection()
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - ElevenLabs Key Section
    @ViewBuilder
    private func elevenLabsKeySection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.orange)
                    Text(Localization.TTS.elevenLabs)
                        .fontWeight(.medium)
                    Spacer()
                    if let destination = URL(string: "https://elevenlabs.io") {
                        Link(Localization.TTS.getAPIKey, destination: destination)
                            .font(.caption)
                    }
                }
                
                HStack {
                    if showElevenLabsKey {
                        TextField(Localization.TTS.elevenLabsKeyPlaceholder, text: $elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(Localization.TTS.elevenLabsKeyPlaceholder, text: $elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showElevenLabsKey.toggle() }) {
                        Image(systemName: showElevenLabsKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                if !elevenLabsKey.isEmpty {
                    Text(String(format: Localization.TTS.maskedKeyFormat, elevenLabsKey.maskedAPIKey))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - OpenAI Key Section
    @ViewBuilder
    private func openAIKeySection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.green)
                    Text(Localization.TTS.openAI)
                        .fontWeight(.medium)
                    Spacer()
                    if let destination = URL(string: "https://platform.openai.com/api-keys") {
                        Link(Localization.TTS.getAPIKey, destination: destination)
                            .font(.caption)
                    }
                }
                
                HStack {
                    if showOpenAIKey {
                        TextField(Localization.TTS.openAIKeyPlaceholder, text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(Localization.TTS.openAIKeyPlaceholder, text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showOpenAIKey.toggle() }) {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                if !openAIKey.isEmpty {
                    Text(String(format: Localization.TTS.maskedKeyFormat, openAIKey.maskedAPIKey))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Google Key Section
    @ViewBuilder
    private func googleKeySection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cloud")
                        .foregroundColor(.blue)
                    Text(Localization.TTS.googleCloudTTS)
                        .fontWeight(.medium)
                    Spacer()
                    if let destination = URL(string: "https://console.cloud.google.com") {
                        Link(Localization.TTS.getAPIKey, destination: destination)
                            .font(.caption)
                    }
                }
                
                HStack {
                    if showGoogleKey {
                        TextField(Localization.TTS.googleKeyPlaceholder, text: $googleKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(Localization.TTS.googleKeyPlaceholder, text: $googleKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showGoogleKey.toggle() }) {
                        Image(systemName: showGoogleKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                if !googleKey.isEmpty {
                    Text(String(format: Localization.TTS.maskedKeyFormat, googleKey.maskedAPIKey))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Managed Provisioning Section
    @ViewBuilder
    private func managedProvisioningSection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.purple)
                    Text(Localization.TTS.managedProvisioning)
                        .fontWeight(.medium)
                    Spacer()
                    if let snapshot = settings.managedAccountSnapshot {
                        Text(String(format: Localization.TTS.managedAccountStatusFormat,
                                    snapshot.planTier.capitalized,
                                    snapshot.billingStatus.capitalized))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(Localization.TTS.enableManagedCredentials, isOn: $managedProvisioningEnabledToggle)

                VStack(alignment: .leading, spacing: 8) {
                    TextField(Localization.TTS.baseURL, text: $managedBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField(Localization.TTS.accountID, text: $managedAccountId)
                        .textFieldStyle(.roundedBorder)
                    TextField(Localization.TTS.planTier, text: $managedPlanTier)
                        .textFieldStyle(.roundedBorder)
                    TextField(Localization.TTS.planStatus, text: $managedPlanStatus)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = settings.managedProvisioningError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button(Localization.TTS.refreshAccount) {
                        Task { await settings.refreshManagedAccountSnapshot(silently: false) }
                    }
                    .disabled(!managedProvisioningEnabledToggle || managedBaseURL.isEmpty || managedAccountId.isEmpty)

                    Button(Localization.TTS.clear, role: .destructive) {
                        settings.clearManagedProvisioning()
                        loadManagedProvisioning()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
