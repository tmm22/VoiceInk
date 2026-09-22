import Foundation
@testable import VoiceInk

extension TTSViewModelTests {
    /// Lifecycle tests must not download models, contact preview URLs or request permissions.
    /// Exercise the real preview task with an asynchronous, cancellation-aware local dependency.
    func makeViewModel() -> TTSViewModel {
        TTSViewModel(
            notificationCenterProvider: { nil },
            previewDataLoader: { _ in
                try await Task.sleep(for: .milliseconds(10))
                throw CancellationError()
            },
            previewAudioGenerator: { _, _, _, _ in
                try await Task.sleep(for: .milliseconds(10))
                throw CancellationError()
            }
        )
    }
}

/// Snapshot of every persisted TTS preference. `TTSViewModel` loads and saves these through
/// `UserDefaults.standard`; without a snapshot the suite would overwrite the developer's real
/// settings (for example, a nil notification center turns TTS notifications off and saves that).
struct TTSDefaultsSnapshot {
    static let keys: [String] = {
        typealias Keys = AppSettings.Keys
        return [
            Keys.ttsSelectedProvider, Keys.ttsPlaybackSpeed, Keys.ttsVolume, Keys.ttsLoopEnabled,
            Keys.ttsIsMinimalistMode, Keys.ttsAudioFormat, Keys.ttsAppearancePreference,
            Keys.ttsNotificationsEnabled, Keys.ttsInspectorEnabled, Keys.ttsStyleValues, Keys.ttsSnippets,
            Keys.ttsPronunciationRules, Keys.ttsElevenLabsPrompt, Keys.ttsElevenLabsModel,
            Keys.ttsElevenLabsTags, Keys.ttsHiddenPocketVoiceIDs, Keys.ttsSelectedTranscriptionProvider,
        ]
    }()

    private let values: [String: Any]

    /// Captures the current values, then clears them so every test starts from the documented
    /// defaults (OpenAI provider, which has a static voice list and never contacts a server on load).
    static func captureAndReset(_ defaults: UserDefaults = .standard) -> TTSDefaultsSnapshot {
        var values: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) { values[key] = value }
            defaults.removeObject(forKey: key)
        }
        return TTSDefaultsSnapshot(values: values)
    }

    func restore(_ defaults: UserDefaults = .standard) {
        for key in Self.keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
