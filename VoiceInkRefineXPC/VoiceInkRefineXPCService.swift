import Foundation

final class VoiceInkRefineXPCService: NSObject, VoiceInkRefineXPCProtocol {
    private let engine = VoiceInkRefineInferenceEngine()
    private let taskLock = NSLock()
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var shutdownTask: Task<Void, Never>?
    private var isShuttingDown = false

    func prepare(
        modelDirectoryPath: String,
        systemPrompt: String,
        requestID: String,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        guard let taskID = UUID(uuidString: requestID), !modelDirectoryPath.isEmpty else {
            reply(
                makeVoiceInkRefineXPCError(
                    .invalidRequest,
                    description: "VoiceInk Refine received an invalid prepare request."
                )
            )
            return
        }

        let didStart = startTask(id: taskID, priority: .utility) {
            [engine] in
            do {
                try await engine.prepare(
                    modelDirectory: URL(fileURLWithPath: modelDirectoryPath),
                    systemPrompt: systemPrompt
                )
                reply(nil)
            } catch {
                reply(
                    makeVoiceInkRefineXPCError(
                        .inferenceFailed,
                        description: error.localizedDescription
                    )
                )
            }
        }
        guard didStart else {
            reply(
                makeVoiceInkRefineXPCError(
                    .connectionFailed,
                    description: "VoiceInk Refine is shutting down."
                )
            )
            return
        }
    }

    func enhance(
        transcript: String,
        modelDirectoryPath: String,
        systemPrompt: String,
        requestID: String,
        withReply reply: @escaping (String?, NSError?) -> Void
    ) {
        guard let taskID = UUID(uuidString: requestID), !modelDirectoryPath.isEmpty else {
            reply(
                nil,
                makeVoiceInkRefineXPCError(
                    .invalidRequest,
                    description: "VoiceInk Refine received an invalid enhancement request."
                )
            )
            return
        }

        let didStart = startTask(id: taskID, priority: .userInitiated) {
            [engine] in
            do {
                let output = try await engine.enhance(
                    transcript: transcript,
                    modelDirectory: URL(fileURLWithPath: modelDirectoryPath),
                    systemPrompt: systemPrompt
                )
                reply(output, nil)
            } catch {
                reply(
                    nil,
                    makeVoiceInkRefineXPCError(
                        .inferenceFailed,
                        description: error.localizedDescription
                    )
                )
            }
        }
        guard didStart else {
            reply(
                nil,
                makeVoiceInkRefineXPCError(
                    .connectionFailed,
                    description: "VoiceInk Refine is shutting down."
                )
            )
            return
        }
    }

    func shutdown(withReply reply: @escaping () -> Void) {
        let shutdownTask = beginShutdownIfNeeded(cancelActiveTasks: false)
        Task(priority: .utility) {
            await shutdownTask.value
            reply()
        }
    }

    func connectionInvalidated() async {
        let shutdownTask = beginShutdownIfNeeded(cancelActiveTasks: true)
        await shutdownTask.value
    }

    private func startTask(
        id: UUID,
        priority: TaskPriority,
        operation: @escaping @Sendable () async -> Void
    ) -> Bool {
        taskLock.lock()
        guard !isShuttingDown else {
            taskLock.unlock()
            return false
        }

        let task = Task(priority: priority) { [weak self] in
            await operation()
            self?.removeTask(id: id)
        }
        activeTasks[id] = task
        taskLock.unlock()
        return true
    }

    private func removeTask(id: UUID) {
        taskLock.lock()
        activeTasks[id] = nil
        taskLock.unlock()
    }

    private func beginShutdownIfNeeded(
        cancelActiveTasks: Bool
    ) -> Task<Void, Never> {
        taskLock.lock()
        if let shutdownTask {
            taskLock.unlock()
            return shutdownTask
        }

        isShuttingDown = true
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        let engine = engine
        let shutdownTask = Task(priority: .utility) {
            if cancelActiveTasks {
                tasks.forEach { $0.cancel() }
            }
            for task in tasks {
                await task.value
            }
            await engine.unload()
        }
        self.shutdownTask = shutdownTask
        taskLock.unlock()
        return shutdownTask
    }
}
