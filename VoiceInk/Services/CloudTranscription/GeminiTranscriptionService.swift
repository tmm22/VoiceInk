import Foundation
import OSLog

/// Gemini transcription service for cloud-based audio transcription
///
/// Uses Google's Gemini API for accurate audio transcription with optimal
/// generation parameters for deterministic, high-quality results.
@MainActor
class GeminiTranscriptionService {
    
    // MARK: - Constants
    
    /// Recommended model for fast, accurate transcription
    private static let recommendedModel = "gemini-2.0-flash"
    
    /// Fallback model if primary is unavailable
    private static let fallbackModel = "gemini-1.5-flash"
    
    /// Optimized transcription prompt for accurate results
    private static let transcriptionPrompt = """
        You are a professional transcription assistant. Transcribe the following audio accurately and completely.
        
        Instructions:
        - Transcribe exactly what is spoken, word for word
        - Include proper punctuation and capitalization
        - Preserve natural speech patterns and pauses where appropriate
        - Do not add any commentary, explanations, or formatting
        - Do not include timestamps unless specifically requested
        - If audio is unclear, transcribe what you can hear accurately
        - Output only the transcribed text, nothing else
        """
    
    // MARK: - Properties
    
    private let session = SecureURLSession.makeEphemeral()
    
    // MARK: - Public Methods
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        AppLogger.network.info("Starting Gemini transcription with model: \(model.name)")
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            AppLogger.network.error("Failed to load audio file at: \(audioURL.lastPathComponent)")
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        AppLogger.network.info("Audio file loaded, size: \(audioData.count) bytes")
        
        let base64AudioData = audioData.base64EncodedString()
        let mimeType = detectMimeType(for: audioURL)
        
        let requestBody = GeminiRequest(
            contents: [
                GeminiContent(
                    parts: [
                        .text(GeminiTextPart(text: Self.transcriptionPrompt)),
                        .audio(GeminiAudioPart(
                            inlineData: GeminiInlineData(
                                mimeType: mimeType,
                                data: base64AudioData
                            )
                        ))
                    ]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.0,  // Deterministic output for consistent transcription
                topP: 1.0,         // Consider all tokens
                topK: 1,           // Most likely token only
                maxOutputTokens: 8192  // Allow for long transcriptions
            )
        )
        
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
            AppLogger.network.info("Request body encoded, sending to Gemini API")
        } catch {
            AppLogger.network.error("Failed to encode Gemini request: \(error.localizedDescription)")
            throw CloudTranscriptionError.dataEncodingError
        }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("Invalid response type from Gemini API")
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            AppLogger.network.error("Gemini API request failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let candidate = transcriptionResponse.candidates.first,
                  let part = candidate.content.parts.first,
                  !part.text.isEmpty else {
                AppLogger.network.error("No transcript found in Gemini response")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            AppLogger.network.info("Gemini transcription successful, text length: \(part.text.count)")
            return part.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let decodingError as DecodingError {
            AppLogger.network.error("Failed to decode Gemini API response: \(decodingError.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        } catch {
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    /// Returns the recommended model name for Gemini transcription
    static func getRecommendedModelName() -> String {
        return recommendedModel
    }
    
    /// Returns available model options for Gemini transcription
    static func getAvailableModels() -> [String] {
        return [recommendedModel, fallbackModel, "gemini-1.5-pro"]
    }
    
    // MARK: - Private Methods
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "Gemini"), !apiKey.isEmpty else {
            AppLogger.network.error("Missing Gemini API key")
            throw CloudTranscriptionError.missingAPIKey
        }
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model.name):generateContent"
        guard let apiURL = URL(string: urlString) else {
            AppLogger.network.error("Failed to construct Gemini API URL for model: \(model.name)")
            throw CloudTranscriptionError.dataEncodingError
        }
        
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name)
    }
    
    /// Detects the appropriate MIME type for the audio file
    private func detectMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mp3"
        case "m4a", "aac":
            return "audio/aac"
        case "ogg":
            return "audio/ogg"
        case "flac":
            return "audio/flac"
        case "webm":
            return "audio/webm"
        default:
            // Default to WAV as it's the most common format in VoiceInk
            return "audio/wav"
        }
    }
    
    // MARK: - Private Types
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
    }
    
    private struct GeminiRequest: Codable {
        let contents: [GeminiContent]
        let generationConfig: GeminiGenerationConfig?
        
        init(contents: [GeminiContent], generationConfig: GeminiGenerationConfig? = nil) {
            self.contents = contents
            self.generationConfig = generationConfig
        }
    }
    
    private struct GeminiGenerationConfig: Codable {
        /// Temperature controls randomness. 0.0 = deterministic, 1.0 = creative
        let temperature: Double
        /// Top-p (nucleus sampling) - cumulative probability threshold
        let topP: Double
        /// Top-k - number of highest probability tokens to consider
        let topK: Int
        /// Maximum number of tokens to generate
        let maxOutputTokens: Int
    }
    
    private struct GeminiContent: Codable {
        let parts: [GeminiPart]
    }
    
    private enum GeminiPart: Codable {
        case text(GeminiTextPart)
        case audio(GeminiAudioPart)
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let textPart):
                try container.encode(textPart)
            case .audio(let audioPart):
                try container.encode(audioPart)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let textPart = try? container.decode(GeminiTextPart.self) {
                self = .text(textPart)
            } else if let audioPart = try? container.decode(GeminiAudioPart.self) {
                self = .audio(audioPart)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid part"))
            }
        }
    }
    
    private struct GeminiTextPart: Codable {
        let text: String
    }
    
    private struct GeminiAudioPart: Codable {
        let inlineData: GeminiInlineData
    }
    
    private struct GeminiInlineData: Codable {
        let mimeType: String
        let data: String
    }
    
    private struct GeminiResponse: Codable {
        let candidates: [GeminiCandidate]
    }
    
    private struct GeminiCandidate: Codable {
        let content: GeminiResponseContent
    }
    
    private struct GeminiResponseContent: Codable {
        let parts: [GeminiResponsePart]
    }
    
    private struct GeminiResponsePart: Codable {
        let text: String
    }
}