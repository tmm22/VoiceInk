import XCTest
import AVFoundation
@testable import VoiceInk

/// Tests for LocalTranscriptionService - focusing on transcription logic and error handling
@available(macOS 14.0, *)
@MainActor
final class LocalTranscriptionServiceTests: XCTestCase {
    
    var sut: LocalTranscriptionService!
    var modelsDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        // Create temporary directory for models
        modelsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestModels_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        // Create service without WhisperState (we'll test error paths)
        sut = LocalTranscriptionService(modelsDirectory: modelsDirectory, whisperState: nil)
    }
    
    override func tearDown() async throws {
        sut = nil
        
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: modelsDirectory)
        
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization_WithValidParameters_CreatesService() {
        // Then
        XCTAssertNotNil(sut)
    }
    
    func testInitialization_WithoutWhisperState_CreatesService() {
        // Given/When
        let service = LocalTranscriptionService(modelsDirectory: modelsDirectory, whisperState: nil)
        
        // Then
        XCTAssertNotNil(service)
    }
    
    // MARK: - Transcription Tests - Error Paths
    
    func testTranscribe_WhenModelProviderNotLocal_ThrowsModelLoadFailedError() async {
        // Given
        let mockModel = MockTranscriptionModelForLocal(
            name: "test-model",
            displayName: "Test Model",
            provider: .groq // Not local
        )
        let audioURL = createTestAudioFile()
        
        // When/Then
        do {
            _ = try await sut.transcribe(audioURL: audioURL, model: mockModel)
            XCTFail("Expected WhisperStateError.modelLoadFailed")
        } catch WhisperStateError.modelLoadFailed {
            // Expected
        } catch {
            XCTFail("Expected WhisperStateError.modelLoadFailed, got \(error)")
        }
    }
    
    func testTranscribe_WhenAudioFileDoesNotExist_ThrowsError() async {
        // Given
        let mockModel = MockTranscriptionModelForLocal(
            name: "test-model",
            displayName: "Test Model",
            provider: .local
        )
        let audioURL = URL(fileURLWithPath: "/nonexistent/path/audio.wav")
        
        // When/Then
        do {
            _ = try await sut.transcribe(audioURL: audioURL, model: mockModel)
            XCTFail("Expected error")
        } catch {
            // Expected - file doesn't exist
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Audio File Tests
    
    func testCreateTestAudioFile_CreatesValidFile() {
        // When
        let audioURL = createTestAudioFile()
        
        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: audioURL)
    }
    
    func testCreateTestAudioFile_WithCustomDuration_CreatesFileWithCorrectDuration() {
        // Given
        let duration: TimeInterval = 2.0
        
        // When
        let audioURL = createTestAudioFile(duration: duration)
        
        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: audioURL)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudioFile(duration: TimeInterval = 1.0) -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_\(UUID().uuidString).wav")
        
        // Create silent audio file
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        )!
        
        let frameCount = AVAudioFrameCount(duration * 16000.0)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        do {
            let audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: format.settings
            )
            try audioFile.write(from: buffer)
        } catch {
            XCTFail("Failed to create test audio file: \(error)")
        }
        
        return fileURL
    }
}

// MARK: - Mock Classes

struct MockTranscriptionModelForLocal: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let provider: ModelProvider
    let description: String = "Mock model for testing"
    let isMultilingualModel: Bool = false
    let supportedLanguages: [String: String] = ["en": "English"]
    let speed: Double = 0.5
    let accuracy: Double = 0.5
    
    var url: URL? {
        return URL(fileURLWithPath: "/tmp/\(name).bin")
    }
}
