import Foundation

/// Operations the lifetime manager needs, with inference kept in one actor turn so
/// concurrent requests cannot overwrite each other's language, prompt, or result.
protocol ManagedWhisperContext: AnyObject, Sendable {
    func transcribe(samples: [Float], language: String?, prompt: String?) async throws -> String
    func releaseResources() async
}

extension WhisperContext: ManagedWhisperContext {
    func transcribe(samples: [Float], language: String?, prompt: String?) throws -> String {
        try Task.checkCancellation()
        setLanguage(language)
        // Each request owns its prompt; nil must clear a previous request's context.
        setPrompt(prompt ?? "")
        guard fullTranscribe(samples: samples) else {
            throw WhisperContextError.transcriptionFailed
        }
        try Task.checkCancellation()
        return getTranscription()
    }
}
