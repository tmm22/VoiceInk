import Foundation

final class OpenAICompatibleTranscriptionService {
    func transcribe(
        audioURL: URL,
        model: CustomCloudModel,
        context: TranscriptionRequestContext
    ) async throws -> String {
        guard let url = URL(string: model.apiEndpoint), SecureEndpointValidator.isAllowed(url) else {
            throw CloudTranscriptionError.networkError(URLError(.unsupportedURL))
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(model.apiKey)", forHTTPHeaderField: "Authorization")

        let bodyURL = try await Task.detached(priority: .utility) {
            try Self.makeRequestBodyFile(
                audioURL: audioURL,
                modelName: model.modelName,
                boundary: boundary,
                context: context
            )
        }.value
        defer {
            // Best-effort cleanup; the temporary file may already have been removed.
            try? FileManager.default.removeItem(at: bodyURL)
        }

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.upload(for: request, fromFile: bodyURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: httpResponse.statusCode,
                message: String(localized: "The transcription provider rejected the request.")
            )
        }

        guard let text = try? JSONDecoder().decode(TranscriptionResponse.self, from: data).text,
            !text.isEmpty
        else {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
        return text
    }

    private nonisolated static func makeRequestBodyFile(
        audioURL: URL,
        modelName: String,
        boundary: String,
        context: TranscriptionRequestContext
    ) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("multipart")
        _ = FileManager.default.createFile(atPath: bodyURL.path, contents: nil)

        do {
            let outputHandle = try FileHandle(forWritingTo: bodyURL)
            defer { try? outputHandle.close() }

            func write(_ string: String) {
                outputHandle.write(Data(string.utf8))
            }
            func writeField(_ name: String, value: String) {
                write("--\(boundary)\r\n")
                write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                write(value)
                write("\r\n")
            }

            write("--\(boundary)\r\n")
            write(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n"
            )
            write("Content-Type: audio/wav\r\n\r\n")

            let inputHandle = try FileHandle(forReadingFrom: audioURL)
            defer { try? inputHandle.close() }
            while let chunk = try inputHandle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                outputHandle.write(chunk)
            }
            write("\r\n")

            writeField("model", value: modelName)
            writeField("response_format", value: "json")
            writeField("temperature", value: "0")
            let language = context.language ?? "auto"
            if language != "auto", !language.isEmpty {
                writeField("language", value: language)
            }
            write("--\(boundary)--\r\n")
            return bodyURL
        } catch {
            // Best-effort cleanup of an incomplete temporary body.
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
    }
}
