import Foundation
import os

class GeminiTranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .gemini

    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "GeminiService")
    private let prompt = "Please transcribe this audio file. Provide only the transcribed text."
    private let pollIntervalNanoseconds: UInt64 = 500_000_000
    private let maxPollingAttempts = 40

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        logger.notice("Starting Gemini transcription with model: \(model.name, privacy: .public)")

        let uploadedFile = try await uploadAudioFile(at: audioURL, apiKey: config.apiKey)

        return try await withUploadedFileCleanup(named: uploadedFile.name, apiKey: config.apiKey) {
            let readyFile = try await waitUntilFileReady(uploadedFile, apiKey: config.apiKey)
            let responseData = try await requestTranscription(for: readyFile, config: config)

            do {
                let transcriptionResponse = try JSONDecoder().decode(GeminiResponse.self, from: responseData)
                guard let candidate = transcriptionResponse.candidates.first,
                      let part = candidate.content.parts.first,
                      !part.text.isEmpty else {
                    logger.error("No transcript found in Gemini response")
                    throw CloudTranscriptionError.noTranscriptionReturned
                }

                logger.notice("Gemini transcription successful, text length: \(part.text.count, privacy: .public)")
                return part.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as CloudTranscriptionError {
                throw error
            } catch {
                logger.error("Failed to decode Gemini API response: \(error.localizedDescription, privacy: .public)")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
        }
    }
}

private extension GeminiTranscriptionService {
    func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "Gemini"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        let path = "v1beta/models/\(model.name):generateContent"
        return APIConfig(
            apiKey: apiKey,
            generateContentURL: try makeAPIURL(path: path, apiKey: apiKey)
        )
    }

    func uploadAudioFile(at audioURL: URL, apiKey: String) async throws -> GeminiFile {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw CloudTranscriptionError.audioFileNotFound
        }

        let uploadStartURL = try makeAPIURL(path: "upload/v1beta/files", apiKey: apiKey)
        let fileSize = try fileSizeInBytes(for: audioURL)
        let mimeType = audioMimeType(for: audioURL)

        var startRequest = URLRequest(url: uploadStartURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue(String(fileSize), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            startRequest.httpBody = try JSONEncoder().encode(StartUploadRequest(file: .init(displayName: audioURL.lastPathComponent)))
        } catch {
            logger.error("Failed to encode Gemini upload metadata: \(error.localizedDescription, privacy: .public)")
            throw CloudTranscriptionError.dataEncodingError
        }

        let (startData, startResponse) = try await session.data(for: startRequest)
        _ = try validateResponse(startResponse, data: startData, logger: logger, providerName: "Gemini upload")

        guard let httpResponse = startResponse as? HTTPURLResponse,
              let uploadURLString = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            logger.error("Gemini upload start response did not include an upload URL")
            throw CloudTranscriptionError.noTranscriptionReturned
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")

        let (uploadData, uploadResponse) = try await session.upload(for: uploadRequest, fromFile: audioURL)
        let responseData = try validateResponse(uploadResponse, data: uploadData, logger: logger, providerName: "Gemini upload")

        do {
            let payload = try JSONDecoder().decode(FileEnvelope.self, from: responseData)
            logger.notice("Gemini file upload complete. Size: \(fileSize, privacy: .public) bytes")
            return payload.file
        } catch {
            logger.error("Failed to decode Gemini upload response: \(error.localizedDescription, privacy: .public)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    func waitUntilFileReady(_ file: GeminiFile, apiKey: String) async throws -> GeminiFile {
        guard let state = file.state else {
            return file
        }

        switch state {
        case .active:
            return file
        case .failed:
            throw CloudTranscriptionError.apiRequestFailed(statusCode: 500, message: "Gemini file processing failed")
        case .processing:
            break
        }

        var currentFile = file
        for _ in 0..<maxPollingAttempts {
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            currentFile = try await fetchFile(named: file.name, apiKey: apiKey)

            switch currentFile.state {
            case .active, .none:
                return currentFile
            case .failed:
                throw CloudTranscriptionError.apiRequestFailed(statusCode: 500, message: "Gemini file processing failed")
            case .processing:
                continue
            }
        }

        throw CloudTranscriptionError.apiRequestFailed(statusCode: 504, message: "Gemini file processing timed out")
    }

    func requestTranscription(for file: GeminiFile, config: APIConfig) async throws -> Data {
        guard let fileURI = file.uri, !fileURI.isEmpty else {
            throw CloudTranscriptionError.noTranscriptionReturned
        }

        var request = URLRequest(url: config.generateContentURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = GeminiRequest(
            contents: [
                GeminiContent(
                    parts: [
                        .text(GeminiTextPart(text: prompt)),
                        .file(GeminiFilePart(fileData: .init(
                            mimeType: file.mimeType ?? "audio/wav",
                            fileURI: fileURI
                        )))
                    ]
                )
            ]
        )

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            logger.error("Failed to encode Gemini request: \(error.localizedDescription, privacy: .public)")
            throw CloudTranscriptionError.dataEncodingError
        }

        let (data, response) = try await session.data(for: request)
        return try validateResponse(response, data: data, logger: logger, providerName: "Gemini")
    }

    func fetchFile(named fileName: String, apiKey: String) async throws -> GeminiFile {
        let url = try makeAPIURL(path: "v1beta/\(fileName)", apiKey: apiKey)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let responseData = try validateResponse(response, data: data, logger: logger, providerName: "Gemini file status")

        do {
            let payload = try JSONDecoder().decode(FileEnvelope.self, from: responseData)
            return payload.file
        } catch {
            logger.error("Failed to decode Gemini file status response: \(error.localizedDescription, privacy: .public)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    func deleteFile(named fileName: String, apiKey: String) async throws {
        let url = try makeAPIURL(path: "v1beta/\(fileName)", apiKey: apiKey)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        _ = try validateResponse(response, data: data, logger: logger, providerName: "Gemini file delete")
    }

    func withUploadedFileCleanup<T>(named fileName: String,
                                    apiKey: String,
                                    operation: () async throws -> T) async throws -> T {
        do {
            let result = try await operation()
            await cleanupUploadedFile(named: fileName, apiKey: apiKey)
            return result
        } catch {
            await cleanupUploadedFile(named: fileName, apiKey: apiKey)
            throw error
        }
    }

    func cleanupUploadedFile(named fileName: String, apiKey: String) async {
        do {
            try await deleteFile(named: fileName, apiKey: apiKey)
        } catch {
            logger.warning("Failed to delete Gemini file \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func fileSizeInBytes(for url: URL) throws -> Int64 {
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        return size.int64Value
    }

    func makeAPIURL(path: String, apiKey: String) throws -> URL {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/\(path)") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw CloudTranscriptionError.dataEncodingError
        }
        return url
    }

    struct APIConfig {
        let apiKey: String
        let generateContentURL: URL
    }

    struct StartUploadRequest: Encodable {
        struct FileMetadata: Encodable {
            let displayName: String

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        let file: FileMetadata
    }

    struct GeminiRequest: Encodable {
        let contents: [GeminiContent]
    }

    struct GeminiContent: Encodable {
        let parts: [GeminiPart]
    }

    enum GeminiPart: Encodable {
        case text(GeminiTextPart)
        case file(GeminiFilePart)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch self {
            case .text(let textPart):
                try container.encode(textPart)
            case .file(let filePart):
                try container.encode(filePart)
            }
        }
    }

    struct GeminiTextPart: Encodable {
        let text: String
    }

    struct GeminiFilePart: Encodable {
        let fileData: GeminiFileData

        enum CodingKeys: String, CodingKey {
            case fileData = "file_data"
        }
    }

    struct GeminiFileData: Encodable {
        let mimeType: String
        let fileURI: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case fileURI = "file_uri"
        }
    }

    struct FileEnvelope: Decodable {
        let file: GeminiFile
    }

    struct GeminiFile: Decodable {
        let name: String
        let uri: String?
        let mimeType: String?
        let state: State?

        enum CodingKeys: String, CodingKey {
            case name
            case uri
            case mimeType = "mimeType"
            case state
        }

        enum State: String, Decodable {
            case active = "ACTIVE"
            case processing = "PROCESSING"
            case failed = "FAILED"
        }
    }

    struct GeminiResponse: Decodable {
        let candidates: [GeminiCandidate]
    }

    struct GeminiCandidate: Decodable {
        let content: GeminiResponseContent
    }

    struct GeminiResponseContent: Decodable {
        let parts: [GeminiResponsePart]
    }

    struct GeminiResponsePart: Decodable {
        let text: String
    }
}
