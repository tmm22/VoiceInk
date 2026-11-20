import CoreAudio
import SwiftUI

@MainActor
struct AudioInputChannelsView: View {
    let deviceID: AudioDeviceID
    @ObservedObject private var deviceManager = AudioDeviceManager.shared

    private var channels: [AudioInputChannel] {
        deviceManager.inputChannelsByDevice[deviceID] ?? []
    }

    private var savedChannels: [UInt32]? {
        deviceManager.selectedInputChannels(for: deviceID)
    }

    private var selectedChannel: UInt32? {
        AudioInputChannelSelection.validatedChannels(savedChannels, deviceChannelCount: UInt32(channels.count))?.first
    }

    private var channelSelection: Binding<UInt32?> {
        Binding(
            get: { selectedChannel },
            set: { deviceManager.setInputChannels($0.map { [$0] }, for: deviceID) }
        )
    }

    var body: some View {
        // Built-in microphone arrays keep their driver-managed automatic configuration.
        if channels.count > 1, !deviceManager.isInternalMicrophone(deviceID) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Input Channel", selection: channelSelection) {
                    Text("Automatic").tag(nil as UInt32?)

                    ForEach(channels) { channel in
                        Text(channelTitle(channel)).tag(Optional(channel.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(deviceManager.isRecordingActive)

                if savedChannels != nil, selectedChannel == nil {
                    Text("Saved input is unavailable. Using Automatic until it returns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if deviceManager.isRecordingActive {
                    Text("Change the input channel after recording stops.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select the input connected to your microphone. Automatic uses the device’s preferred inputs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func channelTitle(_ channel: AudioInputChannel) -> String {
        if let name = channel.name {
            return String(format: String(localized: "Input %u (%@)"), channel.id, name)
        }
        return String(format: String(localized: "Input %u"), channel.id)
    }
}
