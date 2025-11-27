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
    case custom = "Custom"
    case nativeApple = "Native Apple"
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

// A new struct for custom cloud models
struct CustomCloudModel: TranscriptionModel, Codable {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .custom
    let apiEndpoint: String
    // apiKey is no longer stored directly; it's retrieved from Keychain
    // We use a transient property to hold it temporarily during creation/editing
    var transientApiKey: String?
    
    var apiKey: String {
        get { 
            transientApiKey ?? KeychainManager.shared.getAPIKey(for: "custom_model_\(id.uuidString)") ?? "" 
        }
        set {
            transientApiKey = newValue
        }
    }
    
    let modelName: String
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, provider, apiEndpoint, modelName, isMultilingualModel, supportedLanguages
    }

    init(id: UUID = UUID(), name: String, displayName: String, description: String, apiEndpoint: String, apiKey: String, modelName: String, isMultilingual: Bool = true, supportedLanguages: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.transientApiKey = apiKey // Store temporarily; manager must save to Keychain
        self.modelName = modelName
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages ?? PredefinedModels.getLanguageDictionary(isMultilingual: isMultilingual)
    }
    
    // Custom decoding to handle both new (no apiKey) and legacy (with apiKey) formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        // Provider is default .custom, but if encoded, we decode it
        if let decodedProvider = try? container.decode(ModelProvider.self, forKey: .provider) {
            // In a struct let constant, we can't reassign, but since it's defined as `let provider: ModelProvider = .custom` 
            // and typically `Codable` synthesizes it, wait.
            // The original struct had `let provider: ModelProvider = .custom`. 
            // If I implement `init(from:)`, I must assign to all properties.
            // But `provider` has a default value and is a `let`. Swift allows assigning to `let` in `init`.
            // However, the previous definition had it as a property with default value.
            // I'll just assign .custom to match behavior or decode if present.
        }
        // Actually, `let provider: ModelProvider = .custom` implies it's a property.
        // To match previous behavior:
        
        apiEndpoint = try container.decode(String.self, forKey: .apiEndpoint)
        modelName = try container.decode(String.self, forKey: .modelName)
        isMultilingualModel = try container.decode(Bool.self, forKey: .isMultilingualModel)
        supportedLanguages = try container.decode([String: String].self, forKey: .supportedLanguages)
        
        // Legacy handling: Check if we can decode "apiKey" from the container using a dynamic key
        // But I limited CodingKeys. 
        // To support migration at the Model level, I would need to include apiKey in CodingKeys but omit it in encode.
        // Or simpler: Handle migration in CustomModelManager using a separate struct as planned.
        // So here, I will just implement standard decoding excluding apiKey.
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(provider, forKey: .provider)
        try container.encode(apiEndpoint, forKey: .apiEndpoint)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(isMultilingualModel, forKey: .isMultilingualModel)
        try container.encode(supportedLanguages, forKey: .supportedLanguages)
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
    let provider: ModelProvider = .local
    let fileExtension: String
    let downloadURLOverride: String?
    let filenameOverride: String?
    let badges: [String]
    let highlight: String?

    var downloadURL: String {
        downloadURLOverride ?? "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }

    var filename: String {
        if let filenameOverride {
            return filenameOverride
        }
        return "\(name).\(fileExtension)"
    }

    var isMultilingualModel: Bool {
        supportedLanguages.count > 1
    }

    var supportsCoreMLEncoder: Bool {
        fileExtension == "bin" && !name.contains("q5") && !name.contains("q8")
    }

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
        highlight: String? = nil
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
    }
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