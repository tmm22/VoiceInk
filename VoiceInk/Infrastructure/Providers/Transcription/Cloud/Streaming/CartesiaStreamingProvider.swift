import Foundation
import LLMkit
import SwiftData

/// Cartesia Ink 2 streaming provider wrapping `LLMkit.CartesiaStreamingClient`.
///
/// Cartesia closes its event stream after finalization without a distinct end-of-stream
/// acknowledgement, so an empty committed event is emitted when the stream ends after `commit`.
final class CartesiaStreamingProvider: LLMKitStreamingProvider<LLMkit.CartesiaStreamingClient> {
    private let finalizationLock = NSLock()
    private var didRequestFinalization = false

    init(modelContext: ModelContext) {
        super.init(client: LLMkit.CartesiaStreamingClient(), apiKeyProviderName: "Cartesia", modelContext: modelContext)
    }

    override var finishesEventsWhenClientStreamEnds: Bool { true }

    override func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        LLMKitStreamingConnection(model: model.name, language: nil, customVocabulary: [])
    }

    override func willConnect() {
        setFinalizationRequested(false)
    }

    override func willCommit() {
        setFinalizationRequested(true)
    }

    override func clientEventStreamDidEnd() {
        if isFinalizationRequested {
            yield(.committed(text: ""))
        }
    }

    private var isFinalizationRequested: Bool {
        finalizationLock.lock()
        defer { finalizationLock.unlock() }
        return didRequestFinalization
    }

    private func setFinalizationRequested(_ value: Bool) {
        finalizationLock.lock()
        didRequestFinalization = value
        finalizationLock.unlock()
    }
}
