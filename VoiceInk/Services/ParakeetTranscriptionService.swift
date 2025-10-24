import Foundation  
import CoreML  
import AVFoundation  
import FluidAudio  
import os.log  
  
class ParakeetTranscriptionService: TranscriptionService {  
    private var asrManager: AsrManager?  
    private var vadManager: VadManager?  
    private let customModelsDirectory: URL?  
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.parakeet", category: "ParakeetTranscriptionService")
      
    init(customModelsDirectory: URL? = nil) {  
        self.customModelsDirectory = customModelsDirectory  
    }  
  
    func loadModel() async throws {  
        guard asrManager == nil else {  
            logger.notice("🦜 Parakeet models already loaded, skipping")
            return  
        }  

        let manager = AsrManager(config: .default)  
        let models: AsrModels
        
        if let customModelsDirectory = customModelsDirectory {
            models = try await AsrModels.load(from: customModelsDirectory)
        } else {
            // Fallback to FluidAudio's default directory
            logger.notice("🦜 Loading Parakeet models from FluidAudio default directory")
            models = try await AsrModels.downloadAndLoad()
        }
        
        try await manager.initialize(models: models)

        self.asrManager = manager  
    }
  
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {  
        try await loadModel()  
          
        guard let asrManager = asrManager else {
            logger.notice("🦜 ASR manager not initialized, cannot transcribe")
            throw ASRError.notInitialized
        }  
          
        let audioSamples = try readAudioSamples(from: audioURL)  
  
        let durationSeconds = Double(audioSamples.count) / 16000.0  
        let isVADEnabled = UserDefaults.standard.object(forKey: "IsVADEnabled") as? Bool ?? true  
  
        let speechAudio: [Float]  
        if durationSeconds < 20.0 || !isVADEnabled {  
            speechAudio = audioSamples  
        } else {  
            let vadConfig = VadConfig(threshold: 0.7)  
            if vadManager == nil, let customModelsDirectory {  
                do {  
                    vadManager = try await VadManager(  
                        config: vadConfig,  
                        modelDirectory: customModelsDirectory.deletingLastPathComponent()  
                    )  
                } catch {
                    logger.notice("🦜 VAD initialization failed, using full audio: \(error.localizedDescription)")
                }  
            }  
  
            do {
                if let vadManager {
                    let segments = try await vadManager.segmentSpeechAudio(audioSamples)
                    speechAudio = segments.isEmpty ? audioSamples : segments.flatMap { $0 }
                } else {
                    speechAudio = audioSamples
                }
            } catch {
                logger.notice("🦜 VAD segmentation failed, using full audio: \(error.localizedDescription)")
                speechAudio = audioSamples
            }  
        }  
  
        let result = try await asrManager.transcribe(speechAudio)
        
        logger.notice("🦜 Parakeet transcription result: \(result.text)")
          
        return result.text  
    }  
  
    private func readAudioSamples(from url: URL) throws -> [Float] {  
        do {  
            let data = try Data(contentsOf: url)  
            guard data.count > 44 else {  
                throw ASRError.invalidAudioData  
            }  
  
            let floats = stride(from: 44, to: data.count, by: 2).map {  
                return data[$0..<$0 + 2].withUnsafeBytes {  
                    let short = Int16(littleEndian: $0.load(as: Int16.self))  
                    return max(-1.0, min(Float(short) / 32767.0, 1.0))  
                }  
            }  
              
            return floats  
        } catch {  
            throw ASRError.invalidAudioData  
        }  
    }  
      
    func cleanup() {
        asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
    }  
}
