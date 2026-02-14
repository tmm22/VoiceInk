import Foundation

// Enum to differentiate between model providers
enum ModelProvider: String, Codable, Hashable, CaseIterable {
    case local = "Local"
    case parakeet = "Parakeet"
    case fastConformer = "FastConformer"
    case senseVoice = "SenseVoice"
    case groq = "Groq"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case mistral = "Mistral"
    case gemini = "Gemini"
    case soniox = "Soniox"
    case assemblyAI = "AssemblyAI"
    case zai = "ZAI"
    case custom = "Custom"
    case nativeApple = "Native Apple"
    // Future providers can be added here
}

// A unified protocol for any transcription model
protocol TranscriptionModel: Identifiable, Hashable {
    var id: UUID { get }
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: ModelProvider { get }
    
    // Language capabilities
    var isMultilingualModel: Bool { get }
    var supportedLanguages: [String: String] { get }

}

extension TranscriptionModel {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var language: String {
        isMultilingualModel ? "Multilingual" : "English-only"
    }
}

// A new struct for Apple's native models
struct NativeAppleModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .nativeApple
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
}

// A new struct for Parakeet models
struct ParakeetModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .parakeet
    let size: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    var isMultilingualModel: Bool {
        supportedLanguages.count > 1
    }
    let supportedLanguages: [String: String]
}

// A new struct for cloud models
struct CloudModel: TranscriptionModel {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider
    let speed: Double
    let accuracy: Double
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(id: UUID = UUID(), name: String, displayName: String, description: String, provider: ModelProvider, speed: Double, accuracy: Double, isMultilingual: Bool, supportedLanguages: [String: String]) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.provider = provider
        self.speed = speed
        self.accuracy = accuracy
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages
    }
}

/// Custom cloud model with API key stored in Keychain.
struct CustomCloudModel: TranscriptionModel, Codable {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .custom
    let apiEndpoint: String
    let modelName: String
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
    var transientApiKey: String?

    /// API key retrieved from Keychain by model ID.
    var apiKey: String {
        APIKeyManager.shared.getCustomModelAPIKey(forModelId: id) ?? ""
    }

    init(id: UUID = UUID(), name: String, displayName: String, description: String, apiEndpoint: String, modelName: String, isMultilingual: Bool = true, supportedLanguages: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.modelName = modelName
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages ?? PredefinedModels.getLanguageDictionary(isMultilingual: isMultilingual)
        self.transientApiKey = nil
    }

    /// Custom Codable to migrate legacy apiKey from JSON to Keychain.
    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, apiEndpoint, modelName, isMultilingualModel, supportedLanguages
        case apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        apiEndpoint = try container.decode(String.self, forKey: .apiEndpoint)
        modelName = try container.decode(String.self, forKey: .modelName)
        isMultilingualModel = try container.decode(Bool.self, forKey: .isMultilingualModel)
        supportedLanguages = try container.decode([String: String].self, forKey: .supportedLanguages)

        if let legacyApiKey = try container.decodeIfPresent(String.self, forKey: .apiKey), !legacyApiKey.isEmpty {
            APIKeyManager.shared.saveCustomModelAPIKey(legacyApiKey, forModelId: id)
        }
        transientApiKey = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(apiEndpoint, forKey: .apiEndpoint)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(isMultilingualModel, forKey: .isMultilingualModel)
        try container.encode(supportedLanguages, forKey: .supportedLanguages)
    }

    static func isValidSecureEndpoint(_ endpoint: String) -> Bool {
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }
}

struct LocalModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let size: String
    let supportedLanguages: [String: String]
    let description: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let fileExtension: String
    let downloadURLOverride: String?
    let filenameOverride: String?
    let badges: [String]
    let highlight: String?
    let supportsCoreMLEncoder: Bool
    let provider: ModelProvider = .local

    init(
        name: String,
        displayName: String,
        size: String,
        supportedLanguages: [String: String],
        description: String,
        speed: Double,
        accuracy: Double,
        ramUsage: Double,
        fileExtension: String = "bin",
        downloadURLOverride: String? = nil,
        filenameOverride: String? = nil,
        badges: [String] = [],
        highlight: String? = nil,
        supportsCoreMLEncoder: Bool = false
    ) {
        self.name = name
        self.displayName = displayName
        self.size = size
        self.supportedLanguages = supportedLanguages
        self.description = description
        self.speed = speed
        self.accuracy = accuracy
        self.ramUsage = ramUsage
        self.fileExtension = fileExtension
        self.downloadURLOverride = downloadURLOverride
        self.filenameOverride = filenameOverride
        self.badges = badges
        self.highlight = highlight
        self.supportsCoreMLEncoder = supportsCoreMLEncoder
    }

    var downloadURL: String {
        if let override = downloadURLOverride, !override.isEmpty {
            return override
        }
        return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }

    var filename: String {
        if let override = filenameOverride, !override.isEmpty {
            return override
        }
        return "\(name).\(fileExtension)"
    }

    var isMultilingualModel: Bool {
        supportedLanguages.count > 1
    }
} 

struct FastConformerModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .fastConformer
    let size: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let requiresMetal: Bool
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
    let modelURL: String
    let tokenizerURL: String
    let checksum: String?
    let badges: [String]
    let highlight: String?
}

struct SenseVoiceModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .senseVoice
    let size: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
    let modelURL: String
    let tokenizerURL: String
    let badges: [String]
    let highlight: String?
}

// User-imported local models 
struct ImportedLocalModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .local
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(fileBaseName: String) {
        self.name = fileBaseName
        self.displayName = fileBaseName
        self.description = "Imported local model"
        self.isMultilingualModel = true
        self.supportedLanguages = PredefinedModels.getLanguageDictionary(isMultilingual: true, provider: .local)
    }
}
