import Foundation

enum AudioFileLoader {
    static func loadData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
        }.value
    }
}
