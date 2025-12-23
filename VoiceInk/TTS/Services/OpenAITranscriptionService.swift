import Foundation
import UniformTypeIdentifiers

@MainActor
protocol AudioTranscribing {
    func hasCredentials() -> Bool
    func transcribe(fileURL: URL,
                    languageHint: String?) async throws -> (text: String,
                                                            language: String?,
                                                            duration: TimeInterval,
                                                            segments: [TranscriptionSegment])
}

@MainActor
final class OpenAITranscriptionService: AudioTranscribing {
    private let session: URLSession
    private let managedProvisioningClient: ManagedProvisioningClient
    private let keychain: KeychainManager
    private var activeManagedCredential: ManagedCredential?

    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let model = "whisper-1"

    init(session: URLSession = SecureURLSession.makeEphemeral(),
         keychain: KeychainManager = KeychainManager(),
         managedProvisioningClient: ManagedProvisioningClient? = nil) {
        self.session = session
        self.keychain = keychain
        self.managedProvisioningClient = managedProvisioningClient ?? .shared
    }

    func hasCredentials() -> Bool {
        if let apiKey = keychain.getAPIKey(for: "OpenAI"), !apiKey.isEmpty {
            return true
        }
        return managedProvisioningClient.isEnabled && managedProvisioningClient.configuration != nil
    }

    func transcribe(fileURL: URL, languageHint: String? = nil) async throws -> (text: String, language: String?, duration: TimeInterval, segments: [TranscriptionSegment]) {
        let filename = fileURL.lastPathComponent
        let mimeType = Self.mimeType(for: fileURL)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let authorization = try await authorizationHeader()
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        let modelName = self.model
        let bodyURL = try await Task.detached(priority: .utility) {
            try Self.makeBodyFile(
                boundary: boundary,
                model: modelName,
                fileURL: fileURL,
                filename: filename,
                mimeType: mimeType,
                languageHint: languageHint
            )
        }.value
        defer {
            try? FileManager.default.removeItem(at: bodyURL)
        }

        if let fileSize = (try? FileManager.default.attributesOfItem(atPath: bodyURL.path)[.size] as? Int64) {
            request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        }

        do {
            let (data, response) = try await session.upload(for: request, fromFile: bodyURL)

            let responseData = try HTTPResponseHandler.handleResponse(
                response,
                data: data,
                onUnauthorized: {
                    if authorization.usedManagedCredential {
                        self.managedProvisioningClient.invalidateCredential(for: .openAI)
                        self.activeManagedCredential = nil
                    }
                },
                errorMessageDecoder: Self.decodeAPIError,
                clientErrorFormat: "Transcription request failed (%d)",
                serverErrorFormat: "Transcription service unavailable (%d)",
                unexpectedFormat: "Unexpected response: %d"
            )

            let payload = try JSONDecoder().decode(ResponsePayload.self, from: responseData)
            let segments = payload.segments?.enumerated().map { index, segment in
                TranscriptionSegment(
                    id: segment.id ?? index,
                    text: segment.text,
                    startTime: Self.toMilliseconds(segment.start) / 1000,
                    endTime: Self.toMilliseconds(segment.end) / 1000,
                    confidence: segment.avgLogprob
                )
            } ?? []

            return (payload.text ?? "",
                    payload.language,
                    Self.toMilliseconds(payload.duration) / 1000,
                    segments)
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
}

private extension OpenAITranscriptionService {
    func authorizationHeader() async throws -> AuthorizationHeader {
        if let key = keychain.getAPIKey(for: "OpenAI"), !key.isEmpty {
            return AuthorizationHeader(header: "Authorization", value: "Bearer \(key)", usedManagedCredential: false)
        }

        guard let credential = try await managedProvisioningClient.credential(for: .openAI) else {
            throw TTSError.invalidAPIKey
        }
        activeManagedCredential = credential
        return AuthorizationHeader(header: "Authorization", value: "Bearer \(credential.token)", usedManagedCredential: true)
    }

    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            return type
        }
        return "audio/wav"
    }

    nonisolated static func makeBodyFile(boundary: String,
                                         model: String,
                                         fileURL: URL,
                                         filename: String,
                                         mimeType: String,
                                         languageHint: String?) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("multipart")

        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)

        do {
            let bodyHandle = try FileHandle(forWritingTo: bodyURL)
            defer { try? bodyHandle.close() }

            func append(_ string: String) {
                bodyHandle.write(Data(string.utf8))
            }

            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
            append("\(model)\r\n")

            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
            append("verbose_json\r\n")

            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
            append("0\r\n")

            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\nsegment\r\n")

            if let languageHint {
                append("--\(boundary)\r\n")
                append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
                append("\(languageHint)\r\n")
            }

            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
            append("Content-Type: \(mimeType)\r\n\r\n")

            let inputHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? inputHandle.close() }
            while let chunk = try inputHandle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                bodyHandle.write(chunk)
            }

            append("\r\n")
            append("--\(boundary)--\r\n")
        } catch {
            throw TTSError.apiError("Failed to prepare transcription request: \(error.localizedDescription)")
        }

        return bodyURL
    }

    static func toMilliseconds(_ value: Double?) -> TimeInterval {
        guard let value, value.isFinite else { return 0 }
        return max(0, value * 1000)
    }

    struct ResponsePayload: Decodable {
        struct Segment: Decodable {
            let id: Int?
            let text: String
            let start: Double?
            let end: Double?
            let avg_logprob: Double?

            var avgLogprob: Double? { avg_logprob }
        }

        let text: String?
        let language: String?
        let duration: Double?
        let segments: [Segment]?
    }

    struct ErrorPayload: Decodable {
        struct APIError: Decodable {
            let message: String
        }

        let error: APIError
    }

    static func decodeAPIError(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            let trimmed = payload.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        return nil
    }
}
