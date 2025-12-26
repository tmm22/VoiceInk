import Foundation
import os

/// Coordinates inference operations with queue management, progress tracking, and cancellation support
@MainActor
class InferenceCoordinator: ObservableObject {
    // MARK: - Properties
    private let contextManager: WhisperContextManager
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "InferenceCoordinator")

    @Published var isProcessing = false
    @Published var currentProgress: Double = 0.0
    @Published var currentOperation: String = ""

    // Queue management
    private var operationQueue: [InferenceOperation] = []
    private var currentTask: Task<String, Error>?
    private var isCancelled = false

    // MARK: - Initialization
    init(contextManager: WhisperContextManager = .shared) {
        self.contextManager = contextManager
    }

    // MARK: - Public Methods

    /// Queue an inference operation
    func queueInference(modelName: String, audioURL: URL, priority: InferencePriority = .normal) async throws -> String {
        let operation = InferenceOperation(
            id: UUID(),
            modelName: modelName,
            audioURL: audioURL,
            priority: priority,
            createdAt: Date()
        )

        operationQueue.append(operation)
        operationQueue.sort { $0.priority.rawValue > $1.priority.rawValue } // Higher priority first

        logger.info("Queued inference operation for model: \(modelName)")

        // Start processing if not already running
        if !isProcessing {
            try await processNextOperation()
        }

        // Wait for this operation to complete
        return try await waitForOperation(operation.id)
    }

    /// Cancel all pending operations
    func cancelAllOperations() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
        operationQueue.removeAll()
        isProcessing = false
        currentProgress = 0.0
        currentOperation = ""
        logger.info("Cancelled all inference operations")
    }

    /// Cancel specific operation
    func cancelOperation(_ operationId: UUID) {
        operationQueue.removeAll { $0.id == operationId }
        logger.info("Cancelled operation: \(operationId)")
    }

    /// Get queue status
    func getQueueStatus() -> InferenceQueueStatus {
        InferenceQueueStatus(
            isProcessing: isProcessing,
            currentOperation: currentOperation,
            progress: currentProgress,
            queueLength: operationQueue.count,
            nextOperation: operationQueue.first?.modelName
        )
    }

    // MARK: - Private Methods

    private func processNextOperation() async throws {
        guard !operationQueue.isEmpty, !isCancelled else { return }

        let operation = operationQueue.removeFirst()
        isProcessing = true
        currentOperation = "Processing \(operation.modelName)"
        currentProgress = 0.0

        logger.info("Starting inference for model: \(operation.modelName)")

        do {
            currentTask = Task {
                // Update progress
                currentProgress = 0.1
                currentOperation = "Loading model \(operation.modelName)"

                // Perform inference
                let result = try await contextManager.performInference(
                    modelName: operation.modelName,
                    audioURL: operation.audioURL
                )

                currentProgress = 1.0
                currentOperation = "Completed \(operation.modelName)"

                logger.info("Inference completed for model: \(operation.modelName)")
                return result
            }

            let result = try await currentTask!.value

            // Mark operation as completed
            operation.status = .completed
            operation.result = result

            // Process next operation
            try await processNextOperation()

        } catch is CancellationError {
            operation.status = .cancelled
            logger.info("Operation cancelled: \(operation.modelName)")
            throw InferenceCoordinatorError.operationCancelled
        } catch {
            operation.status = .failed
            operation.error = error
            logger.error("Operation failed: \(operation.modelName) - \(error.localizedDescription)")

            // Continue with next operation despite failure
            try await processNextOperation()
            throw error
        }
    }

    private func waitForOperation(_ operationId: UUID) async throws -> String {
        while true {
            if let operation = operationQueue.first(where: { $0.id == operationId }) {
                switch operation.status {
                case .completed:
                    return operation.result ?? ""
                case .failed:
                    throw operation.error ?? InferenceCoordinatorError.operationFailed
                case .cancelled:
                    throw InferenceCoordinatorError.operationCancelled
                case .pending, .processing:
                    try await Task.sleep(for: .milliseconds(100))
                }
            } else {
                // Operation not found, might have been processed
                throw InferenceCoordinatorError.operationNotFound
            }
        }
    }
}

// MARK: - Supporting Types

enum InferencePriority: Int {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
}

class InferenceOperation {
    let id: UUID
    let modelName: String
    let audioURL: URL
    let priority: InferencePriority
    let createdAt: Date
    var status: InferenceStatus = .pending
    var result: String?
    var error: Error?

    init(id: UUID, modelName: String, audioURL: URL, priority: InferencePriority, createdAt: Date) {
        self.id = id
        self.modelName = modelName
        self.audioURL = audioURL
        self.priority = priority
        self.createdAt = createdAt
    }
}

enum InferenceStatus {
    case pending
    case processing
    case completed
    case failed
    case cancelled
}

struct InferenceQueueStatus {
    let isProcessing: Bool
    let currentOperation: String
    let progress: Double
    let queueLength: Int
    let nextOperation: String?
}

// MARK: - Error Types
enum InferenceCoordinatorError: LocalizedError {
    case operationCancelled
    case operationFailed
    case operationNotFound

    var errorDescription: String? {
        switch self {
        case .operationCancelled:
            return "Inference operation was cancelled"
        case .operationFailed:
            return "Inference operation failed"
        case .operationNotFound:
            return "Inference operation not found"
        }
    }
}