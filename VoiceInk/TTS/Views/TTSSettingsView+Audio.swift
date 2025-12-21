import SwiftUI

// MARK: - Audio Settings Section
extension TTSSettingsView {
    @ViewBuilder
    func audioSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Audio Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            GroupBox("Default Settings") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Default Speed:")
                        Picker("", selection: $viewModel.playbackSpeed) {
                            Text("0.5×").tag(0.5)
                            Text("0.75×").tag(0.75)
                            Text("1.0×").tag(1.0)
                            Text("1.25×").tag(1.25)
                            Text("1.5×").tag(1.5)
                            Text("1.75×").tag(1.75)
                            Text("2.0×").tag(2.0)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 100)
                        .onChange(of: viewModel.playbackSpeed) {
                            viewModel.applyPlaybackSpeed(save: true)
                        }
                        Spacer()
                    }
                    
                    HStack {
                        Text("Default Volume:")
                        Slider(value: $viewModel.volume, in: 0...1)
                            .onChange(of: viewModel.volume) {
                                viewModel.applyPlaybackVolume(save: true)
                            }
                            .frame(width: 200)
                        Text("\(Int(viewModel.volume * 100))%")
                            .frame(width: 50)
                            .monospacedDigit()
                        Spacer()
                    }
                    
                    Toggle("Enable Loop by Default", isOn: $viewModel.isLoopEnabled)
                }
                .padding(.vertical, 8)
            }
            
            GroupBox("Audio Quality") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Higher quality settings may increase generation time and cost.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Quality settings would go here
                    Text("Quality settings vary by provider and will be applied automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
        }
        .padding()
    }
}
