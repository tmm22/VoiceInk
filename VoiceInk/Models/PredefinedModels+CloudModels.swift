import Foundation

// MARK: - Cloud Transcription Models
extension PredefinedModels {
    
    /// All cloud-based transcription model definitions from various providers
    static let cloudModels: [any TranscriptionModel] = [
        // Groq Models
        CloudModel(
            name: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo (Groq)",
            description: "Whisper Large v3 Turbo model with Groq's lightning-speed inference",
            provider: .groq,
            speed: 0.65,
            accuracy: 0.96,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .groq)
        ),
        
        // ElevenLabs Models
        CloudModel(
            name: "scribe_v2_realtime",
            displayName: "Scribe v2 Realtime (ElevenLabs)",
            description: "ElevenLabs' latest low-latency transcription model with higher accuracy and word-level timestamps.",
            provider: .elevenLabs,
            speed: 0.9,
            accuracy: 0.99,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .elevenLabs)
        ),
        CloudModel(
            name: "scribe_v1",
            displayName: "Scribe v1 (ElevenLabs)",
            description: "ElevenLabs' Scribe model for fast & accurate transcription.",
            provider: .elevenLabs,
            speed: 0.7,
            accuracy: 0.98,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .elevenLabs)
        ),
        CloudModel(
            name: "scribe_v2",
            displayName: "Scribe v2 (ElevenLabs)",
            description: "ElevenLabs' Scribe v2 model for the most accurate transcription.",
            provider: .elevenLabs,
            speed: 0.75,
            accuracy: 0.99,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .elevenLabs)
        ),
        
        // Deepgram Models
        CloudModel(
            name: "nova-2",
            displayName: "Nova (Deepgram)",
            description: "Deepgram's Nova model for fast, accurate, and cost-effective transcription.",
            provider: .deepgram,
            speed: 0.9,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .deepgram)
        ),
        CloudModel(
            name: "nova-3-medical",
            displayName: "Nova-3 Medical (Deepgram)",
            description: "Specialized medical transcription model optimized for clinical environments.",
            provider: .deepgram,
            speed: 0.9,
            accuracy: 0.96,
            isMultilingual: false,
            supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .deepgram)
        ),
        CloudModel(
            name: "nova-3-diarize",
            displayName: "Nova-3 + Diarization (Deepgram)",
            description: "High-accuracy English transcription with speaker identification. Outputs speaker-labeled segments.",
            provider: .deepgram,
            speed: 0.88,
            accuracy: 0.975,
            isMultilingual: false,
            supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .deepgram)
        ),
        CloudModel(
            name: "nova-2-diarize",
            displayName: "Nova-2 + Diarization (Deepgram)",
            description: "Multilingual transcription with speaker identification. Outputs speaker-labeled segments for all supported languages.",
            provider: .deepgram,
            speed: 0.88,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .deepgram)
        ),
        
        // Mistral Models
        CloudModel(
            name: "voxtral-mini-latest",
            displayName: "Voxtral Mini (Mistral)",
            description: "Mistral's latest SOTA transcription model.",
            provider: .mistral,
            speed: 0.8,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .mistral)
        ),
        
        // Gemini Models
        CloudModel(
            name: "gemini-3-pro-preview",
            displayName: "Gemini 3 Pro",
            description: "Google's most advanced multimodal model with next-generation reasoning and transcription.",
            provider: .gemini,
            speed: 0.6,
            accuracy: 0.98,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .gemini)
        ),
        CloudModel(
            name: "gemini-3-flash-preview",
            displayName: "Gemini 3 Flash",
            description: "Google's fastest Gemini 3 model with frontier intelligence built for speed.",
            provider: .gemini,
            speed: 0.95,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .gemini)
        ),
        
        // Soniox Models
        CloudModel(
            name: "stt-async-v3",
            displayName: "Soniox (stt-async-v3)",
            description: "Soniox asynchronous transcription model v3.",
            provider: .soniox,
            speed: 0.8,
            accuracy: 0.96,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .soniox)
        ),
        
        // AssemblyAI Models
        CloudModel(
            name: "assemblyai-best",
            displayName: "AssemblyAI Best",
            description: "High-accuracy transcription with speaker diarization support.",
            provider: .assemblyAI,
            speed: 0.75,
            accuracy: 0.96,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .assemblyAI)
        ),
        CloudModel(
            name: "assemblyai-nano",
            displayName: "AssemblyAI Nano",
            description: "Fast, cost-effective transcription optimized for speed.",
            provider: .assemblyAI,
            speed: 0.90,
            accuracy: 0.92,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .assemblyAI)
        ),
        
        // Z.AI Models
        CloudModel(
            name: "glm-asr-2512",
            displayName: "GLM-ASR-Nano (Z.AI)",
            description: "Z.AI's open-source speech recognition model with exceptional accuracy (0.0717 CER). Optimized for Chinese, English, Cantonese, and 14+ languages. Max 30 seconds per request.",
            provider: .zai,
            speed: 0.85,
            accuracy: 0.97,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .zai)
        )
    ]
}
