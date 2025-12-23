import SwiftUI

struct OnboardingModelDownloadView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var whisperState: WhisperState
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var isDownloading = false
    @State private var isModelSet = false
    @State private var showTutorial = false
    
    private var turboModel: LocalModel? {
        PredefinedModels.models.first { $0.name == "ggml-large-v3-turbo-q5_0" } as? LocalModel
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                // Reusable background
                OnboardingBackgroundView()
                
                VStack(spacing: 40) {
                    // Model icon and title
                    VStack(spacing: 30) {
                        // Model icon
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 100, height: 100)
                            
                            if isModelSet {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.accentColor)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "brain")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .scaleEffect(scale)
                        .opacity(opacity)
                        
                        // Title and description
                        VStack(spacing: 12) {
                            Text("Download AI Model")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("We'll download the optimized model to get you started.")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .scaleEffect(scale)
                        .opacity(opacity)
                    }
                    
                    // Model card - Centered and compact
                    Group {
                        if let model = turboModel {
                            VStack(alignment: .leading, spacing: 16) {
                                // Model name and details
                                VStack(alignment: .center, spacing: 8) {
                                    Text(model.displayName)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("\(model.size) • \(model.language)")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                                
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                
                                // Performance indicators in a more compact layout
                                HStack(spacing: 20) {
                                    performanceIndicator(label: "Speed", value: model.speed)
                                    performanceIndicator(label: "Accuracy", value: model.accuracy)
                                    ramUsageLabel(gb: model.ramUsage)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                
                                // Download progress
                                if isDownloading {
                                    DownloadProgressView(
                                        modelName: model.name,
                                        downloadProgress: whisperState.downloadProgress,
                                        supportsCoreML: model.supportsCoreMLEncoder
                                    )
                                    .transition(.opacity)
                                }
                            }
                        } else {
                            VStack(spacing: 16) {
                                Text("Model configuration error")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Unable to find the turbo model")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(24)
                    .frame(width: min(geometry.size.width * 0.6, 400))
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .scaleEffect(scale)
                    .opacity(opacity)
                    
                    // Action buttons
                    VStack(spacing: 16) {
                        Button(action: handleAction) {
                            Text(getButtonTitle())
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(Color.accentColor)
                                .cornerRadius(25)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(isDownloading)
                        
                        if !isModelSet {
                            SkipButton(text: "Skip for now") {
                                withAnimation {
                                    showTutorial = true
                                }
                            }
                        }
                    }
                    .opacity(opacity)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: min(geometry.size.width * 0.8, 600))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            
            if showTutorial {
                OnboardingTutorialView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear {
            animateIn()
            checkModelStatus()
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }
    
    private func checkModelStatus() {
        guard let model = turboModel else { return }
        if whisperState.availableModels.contains(where: { $0.name == model.name }) {
            isModelSet = whisperState.currentTranscriptionModel?.name == model.name
        }
    }
    
    private func handleAction() {
        guard let model = turboModel else { return }
        
        if isModelSet {
            withAnimation {
                showTutorial = true
            }
        } else if whisperState.availableModels.contains(where: { $0.name == model.name }) {
            if let modelToSet = whisperState.allAvailableModels.first(where: { $0.name == model.name }) {
                Task {
                    whisperState.setDefaultTranscriptionModel(modelToSet)
                    withAnimation {
                        isModelSet = true
                    }
                }
            }
        } else {
            withAnimation {
                isDownloading = true
            }
            Task {
                await whisperState.downloadModel(model)
                if let modelToSet = whisperState.allAvailableModels.first(where: { $0.name == model.name }) {
                    whisperState.setDefaultTranscriptionModel(modelToSet)
                    withAnimation {
                        isModelSet = true
                        isDownloading = false
                    }
                }
            }
        }
    }
    
    private func getButtonTitle() -> String {
        guard let model = turboModel else { return "Model Error" }
        
        if isModelSet {
            return "Continue"
        } else if isDownloading {
            return "Downloading..."
        } else if whisperState.availableModels.contains(where: { $0.name == model.name }) {
            return "Set as Default"
        } else {
            return "Download Model"
        }
    }
    
    private func performanceIndicator(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(Double(index) / 5.0 <= value ? Color.accentColor : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
    
    private func ramUsageLabel(gb: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RAM")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            Text(String(format: "%.1f GB", gb))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
