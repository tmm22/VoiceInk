import Foundation
import os

class CloudTranscriptionBase {
    let session = SecureURLSession.makeEphemeral()

    func loadAudioData(from url: URL) async throws -> Data {
        do {
            return try await AudioFileLoader.loadData(from: url)
        } catch {
            throw CloudTranscriptionError.audioFileNotFound
        }
    }

    func validateResponse(
        _ response: URLResponse,
        data: Data,
        logger: Logger? = nil,
        providerName: String
    ) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            logger?.error("\(providerName, privacy: .public) API request failed with status \(httpResponse.statusCode): \(errorMessage, privacy: .public)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return data
    }
}
