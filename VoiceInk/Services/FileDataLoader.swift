import Foundation

/// Lightweight async file loader that avoids blocking the caller's actor/thread.
///
/// Notes:
/// - Uses `Data(contentsOf:options:)` with `.mappedIfSafe` by default to reduce peak memory.
/// - Runs in a detached task to avoid blocking the main actor.
enum FileDataLoader {
    static func loadData(from url: URL,
                         options: Data.ReadingOptions = [.mappedIfSafe]) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: url, options: options)
        }.value
    }
}

