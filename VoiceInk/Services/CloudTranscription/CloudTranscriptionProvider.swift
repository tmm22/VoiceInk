import Foundation

protocol CloudTranscriptionProvider {
    var supportedProvider: ModelProvider { get }
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String
}
