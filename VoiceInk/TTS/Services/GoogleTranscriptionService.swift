import Foundation
import AVFoundation

@MainActor
final class GoogleTranscriptionService: AudioTranscribing {
    private struct RecognizeRequest: Encodable {
        struct Config: Encodable, Sendable {
            let encoding: String?
            let sampleRateHertz: Int?
            let languageCode: String
            let model: String
            let enableAutomaticPunctuation: Bool
            let enableWordTimeOffsets: Bool
        }

        struct Audio: Encodable, Sendable {
            let content: String
        }

        let config: Config
        let audio: Audio
    }

    private struct RecognizeResponse: Decodable {
        struct Result: Decodable {
            struct Alternative: Decodable {
                struct Word: Decodable {
                    let startTime: String?
                    let endTime: String?
                    let word: String
                }

                let transcript: String
                let confidence: Double?
                let words: [Word]?
            }

            let alternatives: [Alternative]
            let languageCode: String?
        }

        let results: [Result]

        var combinedTranscript: String {
            results
                .compactMap { $0.alternatives.first?.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        var detectedLanguage: String? {
            results.compactMap { $0.languageCode?.lowercased() }.first
        }
    }

    private struct GoogleErrorEnvelope: Decodable {
        struct ErrorBody: Decodable {
            let message: String
        }

        let error: ErrorBody
    }

    private let session: URLSession
    private let keychain: KeychainManager
    private let model = "chirp"
    private let endpoint = URL(string: "https://speech.googleapis.com/v1/speech:recognize")!

    init(session: URLSession = SecureURLSession.makeEphemeral(),
         keychain: KeychainManager = KeychainManager()) {
        self.session = session
        self.keychain = keychain
    }

    func hasCredentials() -> Bool {
        guard let apiKey = keychain.getAPIKey(for: "Google") else { return false }
        return !apiKey.isEmpty
    }

    func transcribe(fileURL: URL,
                    languageHint: String?) async throws -> (text: String,
                                                            language: String?,
                                                            duration: TimeInterval,
                                                            segments: [TranscriptionSegment]) {
        guard let apiKey = keychain.getAPIKey(for: "Google"), !apiKey.isEmpty else {
            throw TTSError.invalidAPIKey
        }

        let audioMetrics = Self.extractAudioMetrics(from: fileURL)
        let config = RecognizeRequest.Config(
            encoding: Self.encoding(for: fileURL),
            sampleRateHertz: audioMetrics.sampleRate,
            languageCode: (languageHint ?? "en-US").lowercased(),
            model: model,
            enableAutomaticPunctuation: true,
            enableWordTimeOffsets: true
        )
        let bodyURL = try await Task.detached(priority: .utility) {
            try Self.makeRequestBodyFile(config: config, audioFileURL: fileURL)
        }.value
        defer {
            try? FileManager.default.removeItem(at: bodyURL)
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TTSError.apiError("Invalid transcription endpoint")
        }

        // SECURITY NOTE: Google Cloud Speech-to-Text API requires the API key as a URL query parameter.
        // This is the official authentication method for API key-based access per Google's documentation.
        // The connection uses HTTPS, so the key is encrypted in transit.
        // Reference: https://cloud.google.com/speech-to-text/docs/reference/rest
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let requestURL = components.url else {
            throw TTSError.apiError("Unable to prepare transcription request")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        if let fileSize = (try? FileManager.default.attributesOfItem(atPath: bodyURL.path)[.size] as? Int64) {
            request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        }

        do {
            let (data, response) = try await session.upload(for: request, fromFile: bodyURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TTSError.networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                let payload = try JSONDecoder().decode(RecognizeResponse.self, from: data)
                let segments = Self.makeSegments(from: payload, fallbackDuration: audioMetrics.duration)
                let transcript = payload.combinedTranscript
                let language = payload.detectedLanguage ?? (languageHint?.lowercased())
                return (
                    text: transcript,
                    language: language,
                    duration: audioMetrics.duration,
                    segments: segments
                )
            case 401:
                throw TTSError.invalidAPIKey
            case 429:
                throw TTSError.quotaExceeded
            case 400...499:
                if let message = Self.decodeErrorMessage(from: data) {
                    throw TTSError.apiError(message)
                }
                throw TTSError.apiError("Transcription request failed (\(httpResponse.statusCode))")
            case 500...599:
                throw TTSError.apiError("Transcription service unavailable (\(httpResponse.statusCode))")
            default:
                throw TTSError.apiError("Unexpected response: \(httpResponse.statusCode)")
            }
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
}

private extension GoogleTranscriptionService {
    struct AudioMetrics {
        let duration: TimeInterval
        let sampleRate: Int?
    }

    private static func extractAudioMetrics(from url: URL) -> AudioMetrics {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let duration = Double(file.length) / format.sampleRate
            let sampleRate = Int(format.sampleRate.rounded())
            return AudioMetrics(duration: max(0, duration), sampleRate: sampleRate > 0 ? sampleRate : nil)
        } catch {
            return AudioMetrics(duration: 0, sampleRate: nil)
        }
    }

    private static func encoding(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "wav", "wave", "aif", "aiff":
            return "LINEAR16"
        case "flac":
            return "FLAC"
        case "mp3":
            return "MP3"
        case "ogg", "opus":
            return "OGG_OPUS"
        case "amr":
            return "AMR"
        case "awb":
            return "AMR_WB"
        case "mulaw":
            return "MULAW"
        default:
            return nil
        }
    }

    private nonisolated static func makeRequestBodyFile(config: RecognizeRequest.Config, audioFileURL: URL) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)

        do {
            let bodyHandle = try FileHandle(forWritingTo: bodyURL)
            defer { try? bodyHandle.close() }

            let configData = try JSONEncoder().encode(config)
            guard let configString = String(data: configData, encoding: .utf8) else {
                throw TTSError.apiError("Failed to encode transcription config")
            }

            bodyHandle.write(Data("{\"config\":".utf8))
            bodyHandle.write(Data(configString.utf8))
            bodyHandle.write(Data(",\"audio\":{\"content\":\"".utf8))

            let inputHandle = try FileHandle(forReadingFrom: audioFileURL)
            defer { try? inputHandle.close() }
            try writeBase64(from: inputHandle, to: bodyHandle)

            bodyHandle.write(Data("\"}}".utf8))
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.apiError("Failed to prepare transcription request: \(error.localizedDescription)")
        }

        return bodyURL
    }

    nonisolated static func writeBase64(from inputHandle: FileHandle, to outputHandle: FileHandle) throws {
        let chunkSize = 48 * 1024
        var carry = Data()

        while let chunk = try inputHandle.read(upToCount: chunkSize), !chunk.isEmpty {
            var buffer = carry
            buffer.append(chunk)

            let remainder = buffer.count % 3
            let encodeLength = buffer.count - remainder
            if encodeLength > 0 {
                let toEncode = buffer.prefix(encodeLength)
                outputHandle.write(toEncode.base64EncodedData())
                carry = buffer.suffix(remainder)
            } else {
                carry = buffer
            }
        }

        if !carry.isEmpty {
            outputHandle.write(carry.base64EncodedData())
        }
    }

    private static func parseTime(_ value: String?) -> TimeInterval? {
        guard var string = value?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }

        if let range = string.range(of: "s", options: [.backwards, .caseInsensitive]) {
            string.removeSubrange(range)
        }

        return TimeInterval(string)
    }

    private static func makeSegments(from response: RecognizeResponse,
                                     fallbackDuration: TimeInterval) -> [TranscriptionSegment] {
        var segments: [TranscriptionSegment] = []
        var runningEnd: TimeInterval = 0

        for result in response.results {
            guard let alternative = result.alternatives.first else { continue }
            let trimmedTranscript = alternative.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTranscript.isEmpty else { continue }

            let words = alternative.words ?? []
            let start = parseTime(words.first?.startTime) ?? runningEnd
            let end = parseTime(words.last?.endTime) ?? max(start, runningEnd)
            let resolvedEnd: TimeInterval

            if end > start {
                resolvedEnd = end
            } else if fallbackDuration > 0 {
                resolvedEnd = min(fallbackDuration, start + max(0.5, fallbackDuration - runningEnd))
            } else {
                resolvedEnd = start
            }

            segments.append(
                TranscriptionSegment(
                    id: segments.count,
                    text: trimmedTranscript,
                    startTime: start,
                    endTime: resolvedEnd,
                    confidence: alternative.confidence
                )
            )

            runningEnd = max(runningEnd, resolvedEnd)
        }

        if segments.isEmpty, fallbackDuration > 0, !response.combinedTranscript.isEmpty {
            segments.append(
                TranscriptionSegment(
                    id: 0,
                    text: response.combinedTranscript,
                    startTime: 0,
                    endTime: fallbackDuration,
                    confidence: nil
                )
            )
        }

        return segments
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.error.message
    }
}
