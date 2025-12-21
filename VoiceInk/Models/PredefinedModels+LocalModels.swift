import Foundation

// MARK: - Local Whisper Models
extension PredefinedModels {
    
    /// All local Whisper model definitions including standard, quantized, and distilled variants
    static let localModels: [any TranscriptionModel] = [
        // Native Apple Model
        NativeAppleModel(
            name: "apple-speech",
            displayName: "Apple Speech",
            description: "Uses the native Apple Speech framework for transcription. Requires macOS 26.",
            isMultilingualModel: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .nativeApple)
        ),
        
        // Parakeet Models
        ParakeetModel(
            name: "parakeet-tdt-0.6b-v2",
            displayName: "Parakeet V2",
            description: "NVIDIA's Parakeet V2 model optimized for lightning-fast English-only transcription.",
            size: "474 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .parakeet)
        ),
        ParakeetModel(
            name: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet V3",
            description: "NVIDIA's Parakeet V3 model with multilingual support across English and 25 European languages.",
            size: "494 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .parakeet)
        ),
        
        // Standard Whisper Models
        LocalModel(
            name: "ggml-tiny",
            displayName: "Tiny",
            size: "75 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Tiny model, fastest, least accurate",
            speed: 0.95,
            accuracy: 0.6,
            ramUsage: 0.3
        ),
        LocalModel(
            name: "ggml-tiny.en",
            displayName: "Tiny (English)",
            size: "75 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .local),
            description: "Tiny model optimized for English, fastest, least accurate",
            speed: 0.95,
            accuracy: 0.65,
            ramUsage: 0.3
        ),
        LocalModel(
            name: "ggml-base",
            displayName: "Base",
            size: "142 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Base model, good balance between speed and accuracy, supports multiple languages",
            speed: 0.85,
            accuracy: 0.72,
            ramUsage: 0.5
        ),
        LocalModel(
            name: "ggml-base.en",
            displayName: "Base (English)",
            size: "142 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .local),
            description: "Base model optimized for English, good balance between speed and accuracy",
            speed: 0.85,
            accuracy: 0.75,
            ramUsage: 0.5
        ),
        LocalModel(
            name: "ggml-small",
            displayName: "Small",
            size: "488 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Small model, good accuracy with reasonable speed, supports multiple languages",
            speed: 0.7,
            accuracy: 0.82,
            ramUsage: 1.0
        ),
        LocalModel(
            name: "ggml-small.en",
            displayName: "Small (English)",
            size: "488 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .local),
            description: "Small model optimized for English, good accuracy with reasonable speed",
            speed: 0.7,
            accuracy: 0.85,
            ramUsage: 1.0
        ),
        LocalModel(
            name: "ggml-medium",
            displayName: "Medium",
            size: "1.5 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Medium model, high accuracy for most use cases, supports multiple languages",
            speed: 0.5,
            accuracy: 0.9,
            ramUsage: 2.6
        ),
        LocalModel(
            name: "ggml-medium.en",
            displayName: "Medium (English)",
            size: "1.5 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: false, provider: .local),
            description: "Medium model optimized for English, high accuracy for most use cases",
            speed: 0.5,
            accuracy: 0.92,
            ramUsage: 2.6
        ),
        LocalModel(
            name: "ggml-large-v2",
            displayName: "Large v2",
            size: "2.9 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Large model v2, slower than Medium but more accurate",
            speed: 0.3,
            accuracy: 0.96,
            ramUsage: 3.8
        ),
        LocalModel(
            name: "ggml-large-v3",
            displayName: "Large v3",
            size: "2.9 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Large model v3, very slow but most accurate",
            speed: 0.3,
            accuracy: 0.98,
            ramUsage: 3.9
        ),
        LocalModel(
            name: "ggml-large-v3-turbo",
            displayName: "Large v3 Turbo",
            size: "1.5 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Large model v3 Turbo, faster than v3 with similar accuracy",
            speed: 0.75,
            accuracy: 0.97,
            ramUsage: 1.8
        ),
        LocalModel(
            name: "ggml-large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo (Quantized)",
            size: "547 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Quantized version of Large v3 Turbo, faster with slightly lower accuracy",
            speed: 0.75,
            accuracy: 0.95,
            ramUsage: 1.0
        ),
        
        // Distilled and Official Models
        LocalModel(
            name: "distil-whisper-large-v3",
            displayName: "Distil-Whisper Large v3",
            size: "1.5 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Official Distil-Whisper Large v3 optimized for whisper.cpp with 5.8x faster decoding.",
            speed: 0.85,
            accuracy: 0.96,
            ramUsage: 1.4,
            fileExtension: "bin",
            downloadURLOverride: "https://huggingface.co/distil-whisper/distil-large-v3-ggml/resolve/main/ggml-distil-large-v3.bin?download=true",
            filenameOverride: "ggml-distil-large-v3.bin",
            badges: ["Distilled", "Official"],
            highlight: "~45% faster than Whisper Large with near-identical WER."
        ),
        LocalModel(
            name: "whisper-large-v3-turbo-gguf",
            displayName: "Whisper Large v3 Turbo",
            size: "1.5 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .local),
            description: "Official Whisper Large v3 Turbo from whisper.cpp maintainer with 4x faster decoding.",
            speed: 0.8,
            accuracy: 0.97,
            ramUsage: 1.7,
            fileExtension: "bin",
            downloadURLOverride: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true",
            filenameOverride: "ggml-large-v3-turbo.bin",
            badges: ["Turbo", "Official"],
            highlight: "Official whisper.cpp model with aggressive layer pruning for speed."
        ),
        
        // FastConformer Models
        FastConformerModel(
            name: "fastconformer-ctc-en-24500",
            displayName: "FastConformer CTC (1.1B)",
            description: "NVIDIA FastConformer CTC export converted for sherpa-onnx with 4.3% WER on LibriSpeech test-other.",
            size: "1.1 GB",
            speed: 0.9,
            accuracy: 0.975,
            ramUsage: 2.0,
            requiresMetal: true,
            isMultilingualModel: false,
            supportedLanguages: ["en": "English"],
            modelURL: "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-fast-conformer-ctc-en-24500/resolve/main/model.onnx?download=1",
            tokenizerURL: "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-fast-conformer-ctc-en-24500/resolve/main/tokens.txt?download=1",
            checksum: nil,
            badges: ["Fast", "CTC"],
            highlight: "Greedy CTC decoding keeps latency under 250 ms on M-series CPUs."
        ),
        
        // SenseVoice Models
        SenseVoiceModel(
            name: "sensevoice-zh-en-ja-ko-yue",
            displayName: "SenseVoice",
            description: "Alibaba's ultra-fast multilingual ASR optimized for Chinese, English, Japanese, Korean, and Cantonese.",
            size: "234 MB",
            speed: 0.99,
            accuracy: 0.96,
            ramUsage: 0.8,
            isMultilingualModel: true,
            supportedLanguages: ["zh": "Chinese", "yue": "Cantonese", "en": "English", "ja": "Japanese", "ko": "Korean"],
            modelURL: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx?download=true",
            tokenizerURL: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt?download=true",
            badges: ["Fast", "Asian Languages"],
            highlight: "15x faster than Whisper with excellent Asian language support."
        )
    ]
}
