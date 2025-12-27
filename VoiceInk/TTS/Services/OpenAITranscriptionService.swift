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
        request.timeoutInterval = 90

        // Build multipart request body on disk and stream via upload(fromFile:)
        // to avoid loading large audio files into memory.
        let (bodyURL, contentType) = try await Task.detached(priority: .utility) {
            try Self.makeRequestBodyFile(
                fileURL: fileURL,
                filename: filename,
                mimeType: mimeType,
                languageHint: languageHint
            )
        }.value
        defer {
            // Best-effort cleanup; file may already be gone.
            try? FileManager.default.removeItem(at: bodyURL)
        }

        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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

    nonisolated static func makeRequestBodyFile(
        fileURL: URL,
        filename: String,
        mimeType: String,
        languageHint: String?
    ) throws -> (url: URL, contentType: String) {
        let boundary = "Boundary-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("multipart")

        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)

        do {
            let outputHandle = try FileHandle(forWritingTo: bodyURL)
            defer { try? outputHandle.close() }

            func write(_ string: String) {
                outputHandle.write(Data(string.utf8))
            }

            func writeField(name: String, value: String) {
                write("--\(boundary)\r\n")
                write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                write(value)
                write("\r\n")
            }

            // Fields
            // NOTE: Keep this constant local to avoid actor-isolation issues in Swift 6.
            writeField(name: "model", value: "whisper-1")
            writeField(name: "response_format", value: "verbose_json")
            writeField(name: "temperature", value: "0")
            writeField(name: "timestamp_granularities[]", value: "segment")

            if let languageHint {
                writeField(name: "language", value: languageHint)
            }

            // File part header
            write("--\(boundary)\r\n")
            write("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
            write("Content-Type: \(mimeType)\r\n\r\n")

            // Stream the audio bytes into the body file.
            let inputHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? inputHandle.close() }

            let chunkSize = 64 * 1024
            while let chunk = try inputHandle.read(upToCount: chunkSize), !chunk.isEmpty {
                outputHandle.write(chunk)
            }

            write("\r\n")

            // Final boundary
            write("--\(boundary)--\r\n")

        } catch {
            // Cleanup temp file on failure.
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }

        return (bodyURL, "multipart/form-data; boundary=\(boundary)")
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
