import Foundation

enum AudioFileLoader {
    static func loadData(from url: URL) async throws -> Data {
        try await FileDataLoader.loadData(from: url)
    }
}
