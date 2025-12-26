import Foundation

/// Result of a transcription processing operation
struct TranscriptionResult {
    /// The transcribed text
    let text: String

    /// Enhanced text (if AI enhancement was applied)
    let enhancedText: String?

    /// Duration of the audio in seconds
    let duration: TimeInterval

    /// Time taken for transcription in seconds
    let transcriptionDuration: TimeInterval

    /// Time taken for AI enhancement in seconds (if applicable)
    let enhancementDuration: TimeInterval?

    /// Name of the model used for transcription
    let modelName: String

    /// Name of the AI enhancement prompt used (if applicable)
    let promptName: String?

    /// Power mode configuration name (if active)
    let powerModeName: String?

    /// Power mode emoji (if active)
    let powerModeEmoji: String?

    /// AI system message sent (for debugging)
    let aiRequestSystemMessage: String?

    /// AI user message sent (for debugging)
    let aiRequestUserMessage: String?

    /// Captured AI context JSON (for debugging)
    let aiContextJSON: String?

    /// Name of the AI enhancement model used
    let aiEnhancementModelName: String?

    init(
        text: String,
        enhancedText: String? = nil,
        duration: TimeInterval,
        transcriptionDuration: TimeInterval,
        enhancementDuration: TimeInterval? = nil,
        modelName: String,
        promptName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        aiRequestSystemMessage: String? = nil,
        aiRequestUserMessage: String? = nil,
        aiContextJSON: String? = nil,
        aiEnhancementModelName: String? = nil
    ) {
        self.text = text
        self.enhancedText = enhancedText
        self.duration = duration
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.modelName = modelName
        self.promptName = promptName
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
        self.aiRequestSystemMessage = aiRequestSystemMessage
        self.aiRequestUserMessage = aiRequestUserMessage
        self.aiContextJSON = aiContextJSON
        self.aiEnhancementModelName = aiEnhancementModelName
    }
}