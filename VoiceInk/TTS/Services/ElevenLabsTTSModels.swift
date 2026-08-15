import Foundation

struct ElevenLabsRequest: Encodable {
    let text: String
    let model_id: String
    let voice_settings: VoiceSettings
    let pronunciation_dictionary_locators: [[String: String]]?
}

struct VoiceSettings: Codable {
    let stability: Double
    let similarity_boost: Double
    let style: Double
    let use_speaker_boost: Bool
}

struct ElevenLabsError: Codable {
    let detail: ErrorDetail
}

struct ErrorDetail: Codable {
    let message: String
    let status: String?
}

struct VoicesResponse: Codable {
    let voices: [VoiceData]
}

struct VoiceData: Codable {
    let voice_id: String
    let name: String
    let preview_url: String?
    let available_models: [String]?
    let labels: VoiceLabels?
}

struct VoiceLabels: Codable {
    let language: String?
    let gender: String?
    let age: String?
    let accent: String?
    let description: String?
    let use_case: String?
}

extension Voice {
    static var elevenLabsVoices: [Voice] {
        [
            Voice(
                id: "21m00Tcm4TlvDq8ikWAM",
                name: "Rachel",
                language: "en-US",
                gender: .female,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "AZnzlk1XvdvUeBnXmlld",
                name: "Domi",
                language: "en-US",
                gender: .female,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "EXAVITQu4vr4xnSDxMaL",
                name: "Bella",
                language: "en-US",
                gender: .female,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "ErXwobaYiN019PkySvjV",
                name: "Antoni",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "MF3mGyEYCl7XYWbV9V6O",
                name: "Elli",
                language: "en-US",
                gender: .female,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "TxGEqnHWrfWFTfGW9XjX",
                name: "Josh",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "VR6AewLTigWG4xSOukaG",
                name: "Arnold",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "pNInz6obpgDQGcFmaJgB",
                name: "Adam",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            ),
            Voice(
                id: "yoZ06aMxZJJ28mfd3POQ",
                name: "Sam",
                language: "en-US",
                gender: .male,
                provider: .elevenLabs,
                previewURL: nil
            )
        ]
    }
}
