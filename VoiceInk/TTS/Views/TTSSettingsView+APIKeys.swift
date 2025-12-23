import SwiftUI

// MARK: - API Keys Section
extension TTSSettingsView {
    @ViewBuilder
    func apiKeysSection() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("API Keys")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your API keys are stored securely in the macOS Keychain.")
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
                    Text("ElevenLabs")
                        .fontWeight(.medium)
                    Spacer()
                    Link("Get API Key", destination: URL(string: "https://elevenlabs.io")!)
                        .font(.caption)
                }
                
                HStack {
                    if showElevenLabsKey {
                        TextField("Enter your ElevenLabs API key", text: $elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Enter your ElevenLabs API key", text: $elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showElevenLabsKey.toggle() }) {
                        Image(systemName: showElevenLabsKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                if !elevenLabsKey.isEmpty {
                    Text("Key: \(elevenLabsKey.maskedAPIKey)")
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
                    Text("OpenAI")
                        .fontWeight(.medium)
                    Spacer()
                    Link("Get API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
                
                HStack {
                    if showOpenAIKey {
                        TextField("Enter your OpenAI API key", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Enter your OpenAI API key", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showOpenAIKey.toggle() }) {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                if !openAIKey.isEmpty {
                    Text("Key: \(openAIKey.maskedAPIKey)")
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
                    Text("Google Cloud TTS")
                        .fontWeight(.medium)
                    Spacer()
                    Link("Get API Key", destination: URL(string: "https://console.cloud.google.com")!)
                        .font(.caption)
                }
                
                HStack {
                    if showGoogleKey {
                        TextField("Enter your Google Cloud API key", text: $googleKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Enter your Google Cloud API key", text: $googleKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showGoogleKey.toggle() }) {
                        Image(systemName: showGoogleKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                if !googleKey.isEmpty {
                    Text("Key: \(googleKey.maskedAPIKey)")
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
                    Text("Managed Provisioning")
                        .fontWeight(.medium)
                    Spacer()
                    if let snapshot = settings.managedAccountSnapshot {
                        Text("Plan: \(snapshot.planTier.capitalized) • Status: \(snapshot.billingStatus.capitalized)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Enable managed credentials", isOn: $managedProvisioningEnabledToggle)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Base URL", text: $managedBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Account ID", text: $managedAccountId)
                        .textFieldStyle(.roundedBorder)
                    TextField("Plan Tier", text: $managedPlanTier)
                        .textFieldStyle(.roundedBorder)
                    TextField("Plan Status", text: $managedPlanStatus)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = settings.managedProvisioningError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button("Refresh Account") {
                        Task { await settings.refreshManagedAccountSnapshot(silently: false) }
                    }
                    .disabled(!managedProvisioningEnabledToggle || managedBaseURL.isEmpty || managedAccountId.isEmpty)

                    Button("Clear", role: .destructive) {
                        settings.clearManagedProvisioning()
                        loadManagedProvisioning()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
