import Foundation
import os

struct MultipartFormField {
    let name: String
    let value: String
}

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
            logger?.error(
                "\(providerName, privacy: .public) API request failed. \(AppLogger.responseMetadata(statusCode: httpResponse.statusCode, responseSize: data.count), privacy: .public)"
            )
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return data
    }

    func uploadMultipartForm(
        _ request: URLRequest,
        audioURL: URL,
        fileFieldName: String = "file",
        mimeType: String? = nil,
        fields: [MultipartFormField]
    ) async throws -> (Data, URLResponse) {
        let (bodyURL, contentType) = try makeMultipartBodyFile(
            audioURL: audioURL,
            fileFieldName: fileFieldName,
            mimeType: mimeType ?? audioMimeType(for: audioURL),
            fields: fields
        )
        defer {
            // Best-effort cleanup; file may already be gone.
            try? FileManager.default.removeItem(at: bodyURL)
        }

        var uploadRequest = request
        uploadRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let fileSize = (try? FileManager.default.attributesOfItem(atPath: bodyURL.path)[.size] as? Int64) {
            uploadRequest.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        }

        do {
            return try await session.upload(for: uploadRequest, fromFile: bodyURL)
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain {
                throw CloudTranscriptionError.audioFileNotFound
            }
            throw error
        }
    }

    func audioMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "m4a", "mp4":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        case "webm":
            return "audio/webm"
        case "ogg", "oga":
            return "audio/ogg"
        case "aif", "aiff":
            return "audio/aiff"
        case "mov":
            return "video/quicktime"
        default:
            return "application/octet-stream"
        }
    }

    private func makeMultipartBodyFile(
        audioURL: URL,
        fileFieldName: String,
        mimeType: String,
        fields: [MultipartFormField]
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

            for field in fields {
                write("--\(boundary)\r\n")
                write("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
                write(field.value)
                write("\r\n")
            }

            write("--\(boundary)\r\n")
            write("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
            write("Content-Type: \(mimeType)\r\n\r\n")

            let inputHandle = try FileHandle(forReadingFrom: audioURL)
            defer { try? inputHandle.close() }

            let chunkSize = 64 * 1024
            while let chunk = try inputHandle.read(upToCount: chunkSize), !chunk.isEmpty {
                outputHandle.write(chunk)
            }

            write("\r\n")
            write("--\(boundary)--\r\n")
            return (bodyURL, "multipart/form-data; boundary=\(boundary)")
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }
    }
}
