import Foundation

struct AudioInputFailurePresentation {
    let title: String
    let actionLabel: String
    let action: () -> Void

    @MainActor
    static func noUsableMicrophone(
        builtInBlockedByClosedLid: Bool
    ) -> AudioInputFailurePresentation {
        let title = builtInBlockedByClosedLid
            ? String(
                localized:
                    "No usable microphone is available. Open the lid or connect an external microphone."
            )
            : String(localized: "No usable microphone is available. Choose a microphone in Audio Settings.")

        return AudioInputFailurePresentation(
            title: title,
            actionLabel: String(localized: "Audio Settings"),
            action: AudioSetupNavigator.openAudioSettings
        )
    }
}

extension VoiceInkEngine {
    @MainActor
    func recordingAudioFailure(
        for error: Error
    ) -> (title: String, actionLabel: String, action: () -> Void)? {
        guard let recorderError = error as? Recorder.RecorderError,
            case .noUsableMicrophone(let builtInBlockedByClosedLid) = recorderError
        else {
            return nil
        }

        let presentation = AudioInputFailurePresentation.noUsableMicrophone(
            builtInBlockedByClosedLid: builtInBlockedByClosedLid
        )
        return (presentation.title, presentation.actionLabel, presentation.action)
    }
}
