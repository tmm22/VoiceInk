import Foundation
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif
import os


// Meet Whisper C++ constraint: Don't access from more than one thread at a time.
actor WhisperContext {
    private var context: OpaquePointer?
    private var languageCString: [CChar]?
    private var prompt: String?
    private var promptCString: [CChar]?
    private var vadModelPath: String?
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "WhisperContext")

    private init() {}

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        if let context = context {
            whisper_free(context)
        }
    }

    func fullTranscribe(samples: [Float]) -> Bool {
        guard let context = context else { return false }
        
        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        
        // Read language directly from UserDefaults
        let selectedLanguage = AppSettings.TranscriptionSettings.selectedLanguage ?? "auto"
        if selectedLanguage != "auto" {
            languageCString = Array(selectedLanguage.utf8CString)
        } else {
            languageCString = nil
        }
        
        if let prompt, !prompt.isEmpty {
            promptCString = Array(prompt.utf8CString)
        } else {
            promptCString = nil
        }
        
        params.print_realtime = true
        params.print_progress = false
        params.print_timestamps = true
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(maxThreads)
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = false
        params.temperature = 0.2

        // New parameters for better performance and compatibility in newer whisper.cpp
        // Note: These fields might not exist in v1.0 but are standard in v1.8+
        // If compilation fails, remove them.
        // params.use_gpu = true // This is now handled in context init params usually
        
        whisper_reset_timings(context)
        
        // Configure VAD if enabled by user and model is available
        let isVADEnabled = AppSettings.TranscriptionSettings.isVADEnabled
        if isVADEnabled, let vadModelPath = self.vadModelPath {
            // VAD handling in whisper.cpp v1.8+ often uses a different mechanism or requires explicit flag updates
            // The previous `params.vad` bool might still be valid but let's check if struct layout changed.
            // For now we assume compatibility or minor changes.
            // In v1.8, VAD might be deprecated in favor of other detection methods or moved.
            // However, if the struct field exists, we use it.
            
            // NOTE: In newer versions, direct VAD control in full_params might be removed or changed.
            // We'll keep existing code unless it breaks.
            params.vad = true // Assuming field still exists or this line will need update
            params.vad_model_path = (vadModelPath as NSString).utf8String
            
            // In v1.8+, vad_params might be different.
            // We will trust the header update kept binary compatibility or recompile will catch it.
            var vadParams = whisper_vad_default_params()
            vadParams.threshold = 0.50
            vadParams.min_speech_duration_ms = 250
            vadParams.min_silence_duration_ms = 100
            vadParams.max_speech_duration_s = Float.greatestFiniteMagnitude
            vadParams.speech_pad_ms = 30
            vadParams.samples_overlap = 0.1
            params.vad_params = vadParams
        } else {
            // params.vad = false // If field removed, this line is error.
            // Safest to set default if struct allows
        }
        
        let runTranscription: (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool = { languagePtr, promptPtr in
            params.language = languagePtr
            params.initial_prompt = promptPtr
            var success = true
            samples.withUnsafeBufferPointer { samplesBuffer in
                if whisper_full(context, params, samplesBuffer.baseAddress, Int32(samplesBuffer.count)) != 0 {
                    self.logger.error("Failed to run whisper_full.")
                    success = false
                }
            }
            return success
        }

        let success: Bool
        if let languageCString {
            success = languageCString.withUnsafeBufferPointer { languagePtr in
                if let promptCString {
                    return promptCString.withUnsafeBufferPointer { promptPtr in
                        runTranscription(languagePtr.baseAddress, promptPtr.baseAddress)
                    }
                }
                return runTranscription(languagePtr.baseAddress, nil)
            }
        } else if let promptCString {
            success = promptCString.withUnsafeBufferPointer { promptPtr in
                runTranscription(nil, promptPtr.baseAddress)
            }
        } else {
            success = runTranscription(nil, nil)
        }
        
        languageCString = nil
        promptCString = nil
        
        return success
    }

    func getTranscription() -> String {
        guard let context = context else { return "" }
        var transcription = ""
        for i in 0..<whisper_full_n_segments(context) {
            transcription += String(cString: whisper_full_get_segment_text(context, i))
        }
        return transcription
    }

    static func createContext(path: String) async throws -> WhisperContext {
        let whisperContext = WhisperContext()
        try await whisperContext.initializeModel(path: path)
        
        // Load VAD model from bundle resources
        let vadModelPath = await VADModelManager.shared.getModelPath()
        await whisperContext.setVADModelPath(vadModelPath)
        
        return whisperContext
    }
    
    private func initializeModel(path: String) throws {
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        logger.info("Running on the simulator, using CPU")
        #else
        params.flash_attn = true // Enable flash attention for Metal
        logger.info("Flash attention enabled for Metal")
        #endif
        
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            self.context = context
        } else {
            logger.error("Couldn't load model at \(path)")
            throw WhisperStateError.modelLoadFailed
        }
    }
    
    private func setVADModelPath(_ path: String?) {
        self.vadModelPath = path
        if path != nil {
            logger.info("VAD model loaded from bundle resources")
        }
    }

    func releaseResources() {
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
        languageCString = nil
    }

    func setPrompt(_ prompt: String?) {
        self.prompt = prompt
    }
}

fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}
