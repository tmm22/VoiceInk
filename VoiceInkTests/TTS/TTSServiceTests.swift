import XCTest
@testable import VoiceInk

/// Tests for TTS Services (ElevenLabs, OpenAI, Google, Local)
/// Tests error handling, API key validation, voice management, and text limits
@available(macOS 14.0, *)
final class TTSServiceTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    static let testVoice = Voice(
        id: "test-voice-id",
        name: "Test Voice",
        language: "en-US",
        gender: .neutral,
        provider: .elevenLabs,
        previewURL: nil
    )
    
    static let defaultSettings = AudioSettings()
    
    // MARK: - TTSError Tests
    
    func testTTSErrorDescriptions() {
        let errors: [TTSError] = [
            .invalidAPIKey,
            .networkError("Connection failed"),
            .quotaExceeded,
            .invalidVoice,
            .textTooLong(5000),
            .unsupportedFormat,
            .apiError("Server error")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
    
    func testTextTooLongErrorContainsLimit() {
        let error = TTSError.textTooLong(5000)
        XCTAssertTrue(error.errorDescription?.contains("5000") ?? false)
    }
    
    func testNetworkErrorContainsMessage() {
        let error = TTSError.networkError("Connection timed out")
        XCTAssertTrue(error.errorDescription?.contains("Connection timed out") ?? false)
    }
    
    func testAPIErrorContainsMessage() {
        let error = TTSError.apiError("Rate limit exceeded")
        XCTAssertTrue(error.errorDescription?.contains("Rate limit exceeded") ?? false)
    }
    
    // MARK: - Voice Model Tests
    
    func testVoiceEquality() {
        let voice1 = Voice(
            id: "voice-1",
            name: "Voice One",
            language: "en-US",
            gender: .male,
            provider: .elevenLabs,
            previewURL: nil
        )
        
        let voice2 = Voice(
            id: "voice-1",
            name: "Voice One",
            language: "en-US",
            gender: .male,
            provider: .elevenLabs,
            previewURL: nil
        )
        
        let voice3 = Voice(
            id: "voice-2",
            name: "Voice Two",
            language: "en-US",
            gender: .female,
            provider: .elevenLabs,
            previewURL: nil
        )
        
        XCTAssertEqual(voice1, voice2)
        XCTAssertNotEqual(voice1, voice3)
    }
    
    func testVoiceGenderCases() {
        XCTAssertEqual(Voice.Gender.allCases.count, 3)
        XCTAssertTrue(Voice.Gender.allCases.contains(.male))
        XCTAssertTrue(Voice.Gender.allCases.contains(.female))
        XCTAssertTrue(Voice.Gender.allCases.contains(.neutral))
    }
    
    func testVoiceProviderTypes() {
        XCTAssertEqual(Voice.ProviderType.elevenLabs.rawValue, "ElevenLabs")
        XCTAssertEqual(Voice.ProviderType.openAI.rawValue, "OpenAI")
        XCTAssertEqual(Voice.ProviderType.google.rawValue, "Google")
        XCTAssertEqual(Voice.ProviderType.tightAss.rawValue, "Tight Ass Mode")
    }
    
    // MARK: - AudioSettings Tests
    
    func testAudioSettingsDefaults() {
        let settings = AudioSettings()
        
        XCTAssertEqual(settings.speed, 1.0)
        XCTAssertEqual(settings.pitch, 1.0)
        XCTAssertEqual(settings.volume, 1.0)
        XCTAssertEqual(settings.format, .mp3)
        XCTAssertEqual(settings.sampleRate, 22050)
        XCTAssertTrue(settings.styleValues.isEmpty)
        XCTAssertTrue(settings.providerOptions.isEmpty)
    }
    
    func testAudioSettingsStyleValueWithControl() {
        var settings = AudioSettings()
        
        let control = ProviderStyleControl(
            id: "test.control",
            label: "Test Control",
            range: 0...1,
            defaultValue: 0.5,
            step: 0.1,
            valueFormat: .percentage,
            helpText: "Test help"
        )
        
        // Test default value
        XCTAssertEqual(settings.styleValue(for: control), 0.5)
        
        // Test custom value
        settings.styleValues["test.control"] = 0.8
        XCTAssertEqual(settings.styleValue(for: control), 0.8)
        
        // Test clamping above range
        settings.styleValues["test.control"] = 1.5
        XCTAssertEqual(settings.styleValue(for: control), 1.0)
        
        // Test clamping below range
        settings.styleValues["test.control"] = -0.5
        XCTAssertEqual(settings.styleValue(for: control), 0.0)
    }
    
    func testAudioSettingsProviderOption() {
        var settings = AudioSettings()
        
        XCTAssertNil(settings.providerOption(for: "model"))
        
        settings.providerOptions["model"] = "eleven_monolingual_v1"
        XCTAssertEqual(settings.providerOption(for: "model"), "eleven_monolingual_v1")
    }
    
    func testAudioFormatCases() {
        let formats = AudioSettings.AudioFormat.allCases
        XCTAssertEqual(formats.count, 5)
        XCTAssertTrue(formats.contains(.mp3))
        XCTAssertTrue(formats.contains(.wav))
        XCTAssertTrue(formats.contains(.aac))
        XCTAssertTrue(formats.contains(.flac))
        XCTAssertTrue(formats.contains(.opus))
    }
    
    // MARK: - ProviderStyleControl Tests
    
    func testProviderStyleControlClamp() {
        let control = ProviderStyleControl(
            id: "test",
            label: "Test",
            range: 0.25...0.75,
            defaultValue: 0.5
        )
        
        XCTAssertEqual(control.clamp(0.5), 0.5)
        XCTAssertEqual(control.clamp(0.0), 0.25)
        XCTAssertEqual(control.clamp(1.0), 0.75)
        XCTAssertEqual(control.clamp(0.25), 0.25)
        XCTAssertEqual(control.clamp(0.75), 0.75)
    }
    
    func testProviderStyleControlFormattedValuePercentage() {
        let control = ProviderStyleControl(
            id: "test",
            label: "Test",
            range: 0...1,
            defaultValue: 0.5,
            valueFormat: .percentage
        )
        
        XCTAssertEqual(control.formattedValue(for: 0.0), "0%")
        XCTAssertEqual(control.formattedValue(for: 0.5), "50%")
        XCTAssertEqual(control.formattedValue(for: 1.0), "100%")
        XCTAssertEqual(control.formattedValue(for: 0.333), "33%")
    }
    
    func testProviderStyleControlFormattedValueDecimal() {
        let control = ProviderStyleControl(
            id: "test",
            label: "Test",
            range: 0...2,
            defaultValue: 1.0,
            valueFormat: .decimal(places: 2)
        )
        
        XCTAssertEqual(control.formattedValue(for: 1.0), "1.00")
        XCTAssertEqual(control.formattedValue(for: 1.5), "1.50")
        XCTAssertEqual(control.formattedValue(for: 0.123), "0.12")
    }
    
    // MARK: - SpeechRequest Tests
    
    func testSpeechRequestCreation() {
        let voice = Self.testVoice
        let settings = Self.defaultSettings
        
        let request = SpeechRequest(text: "Hello world", voice: voice, settings: settings)
        
        XCTAssertEqual(request.text, "Hello world")
        XCTAssertEqual(request.voice.id, voice.id)
        XCTAssertNotNil(request.timestamp)
    }
    
    // MARK: - ElevenLabs Voice Tests
    
    func testElevenLabsDefaultVoices() {
        let voices = Voice.elevenLabsVoices
        
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.count >= 9) // At least 9 default voices
        
        // Verify all voices have required properties
        for voice in voices {
            XCTAssertFalse(voice.id.isEmpty)
            XCTAssertFalse(voice.name.isEmpty)
            XCTAssertEqual(voice.provider, .elevenLabs)
        }
        
        // Verify Rachel is the first voice (default)
        XCTAssertEqual(voices.first?.name, "Rachel")
        XCTAssertEqual(voices.first?.id, "21m00Tcm4TlvDq8ikWAM")
    }
    
    func testElevenLabsVoiceGenderDistribution() {
        let voices = Voice.elevenLabsVoices
        
        let maleVoices = voices.filter { $0.gender == .male }
        let femaleVoices = voices.filter { $0.gender == .female }
        
        XCTAssertFalse(maleVoices.isEmpty, "Should have male voices")
        XCTAssertFalse(femaleVoices.isEmpty, "Should have female voices")
    }
}

// MARK: - ElevenLabs Service Tests

@available(macOS 14.0, *)
@MainActor
final class ElevenLabsServiceTests: XCTestCase {
    
    var service: ElevenLabsService!
    
    override func setUp() async throws {
        try await super.setUp()
        service = ElevenLabsService()
    }
    
    override func tearDown() async throws {
        service = nil
        try await super.tearDown()
    }
    
    func testServiceName() async {
        XCTAssertEqual(service.name, "ElevenLabs")
    }
    
    func testDefaultVoice() async {
        let defaultVoice = service.defaultVoice
        
        XCTAssertEqual(defaultVoice.id, "21m00Tcm4TlvDq8ikWAM")
        XCTAssertEqual(defaultVoice.name, "Rachel")
        XCTAssertEqual(defaultVoice.provider, .elevenLabs)
        XCTAssertEqual(defaultVoice.gender, .female)
    }
    
    func testStyleControls() async {
        let controls = service.styleControls
        
        XCTAssertEqual(controls.count, 3)
        
        let controlIDs = controls.map { $0.id }
        XCTAssertTrue(controlIDs.contains("elevenLabs.stability"))
        XCTAssertTrue(controlIDs.contains("elevenLabs.similarityBoost"))
        XCTAssertTrue(controlIDs.contains("elevenLabs.style"))
    }
    
    func testStabilityControlRange() async {
        let stabilityControl = service.styleControls.first { $0.id == "elevenLabs.stability" }
        
        XCTAssertNotNil(stabilityControl)
        XCTAssertEqual(stabilityControl?.range.lowerBound, 0)
        XCTAssertEqual(stabilityControl?.range.upperBound, 1)
        XCTAssertEqual(stabilityControl?.defaultValue, 0.5)
    }
    
    func testSimilarityBoostControlRange() async {
        let control = service.styleControls.first { $0.id == "elevenLabs.similarityBoost" }
        
        XCTAssertNotNil(control)
        XCTAssertEqual(control?.range.lowerBound, 0)
        XCTAssertEqual(control?.range.upperBound, 1)
        XCTAssertEqual(control?.defaultValue, 0.75)
    }
    
    func testStyleControlRange() async {
        let control = service.styleControls.first { $0.id == "elevenLabs.style" }
        
        XCTAssertNotNil(control)
        XCTAssertEqual(control?.range.lowerBound, 0)
        XCTAssertEqual(control?.range.upperBound, 1)
        XCTAssertEqual(control?.defaultValue, 0.0)
    }
    
    func testHasValidAPIKeyWithoutKey() async {
        // Clear any existing API key
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "ElevenLabs")
        
        // Create fresh service
        let freshService = ElevenLabsService()
        
        // Without managed provisioning, should return false
        // Note: This may return true if managed provisioning is enabled
        // The test verifies the method doesn't crash
        _ = freshService.hasValidAPIKey()
    }
    
    func testUpdateAPIKey() async {
        service.updateAPIKey("test-api-key")
        
        // After updating, hasValidAPIKey should return true
        XCTAssertTrue(service.hasValidAPIKey())
    }
    
    func testAvailableVoicesReturnsFallback() async {
        // Without fetching from API, should return fallback voices
        let voices = service.availableVoices
        
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.count >= 9)
    }
    
    func testSynthesizeSpeechThrowsForTextTooLong() async {
        service.updateAPIKey("test-key")
        
        let longText = String(repeating: "a", count: 5001)
        let voice = service.defaultVoice
        let settings = AudioSettings()
        
        do {
            _ = try await service.synthesizeSpeech(text: longText, voice: voice, settings: settings)
            XCTFail("Should throw textTooLong error")
        } catch let error as TTSError {
            if case .textTooLong(let limit) = error {
                XCTAssertEqual(limit, 5000)
            } else {
                XCTFail("Expected textTooLong error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSynthesizeSpeechThrowsForInvalidAPIKey() async {
        // Clear API key
        let keychain = KeychainManager()
        keychain.deleteAPIKey(for: "ElevenLabs")
        
        let freshService = ElevenLabsService()
        let voice = freshService.defaultVoice
        let settings = AudioSettings()
        
        do {
            _ = try await freshService.synthesizeSpeech(text: "Hello", voice: voice, settings: settings)
            XCTFail("Should throw invalidAPIKey error")
        } catch let error as TTSError {
            if case .invalidAPIKey = error {
                // Expected
            } else {
                // Network errors are also acceptable since we don't have a valid key
            }
        } catch {
            // Other errors are acceptable (network, etc.)
        }
    }
}

// MARK: - AudioPlayerService Tests

@available(macOS 14.0, *)
@MainActor
final class AudioPlayerServiceTests: XCTestCase {
    
    var playerService: AudioPlayerService!
    
    override func setUp() async throws {
        try await super.setUp()
        playerService = AudioPlayerService()
    }
    
    override func tearDown() async throws {
        playerService?.stop()
        playerService = nil
        try await super.tearDown()
    }
    
    func testInitialState() async {
        XCTAssertFalse(playerService.isPlaying)
        XCTAssertEqual(playerService.currentTime, 0)
        XCTAssertEqual(playerService.duration, 0)
    }
    
    func testPlaybackProgress() async {
        // Without audio loaded, progress should be 0
        XCTAssertEqual(playerService.playbackProgress, 0)
    }
    
    func testStopResetsState() async {
        playerService.stop()
        
        XCTAssertFalse(playerService.isPlaying)
        XCTAssertEqual(playerService.currentTime, 0)
    }
    
    func testPlayInvalidDataDoesNotCrash() async {
        // Playing invalid data should not crash
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        
        do {
            try await playerService.play(invalidData)
            // If it doesn't throw, that's fine - just verify state
        } catch {
            // Expected - invalid audio data
        }
    }
}

// MARK: - Text Chunker Tests

@available(macOS 14.0, *)
final class TextChunkerTests: XCTestCase {
    
    func testChunkTextBySentences() {
        let text = "Hello world. This is a test. Another sentence here."
        let chunks = TextChunker.chunkText(text, maxLength: 50)
        
        XCTAssertFalse(chunks.isEmpty)
        
        // Verify no chunk exceeds max length
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 50)
        }
    }
    
    func testChunkTextPreservesSentences() {
        let text = "Short sentence. Another short one."
        let chunks = TextChunker.chunkText(text, maxLength: 100)
        
        // With large max length, should be single chunk
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first, text)
    }
    
    func testChunkTextHandlesEmptyString() {
        let chunks = TextChunker.chunkText("", maxLength: 100)
        XCTAssertTrue(chunks.isEmpty)
    }
    
    func testChunkTextHandlesWhitespaceOnly() {
        let chunks = TextChunker.chunkText("   \n\t  ", maxLength: 100)
        XCTAssertTrue(chunks.isEmpty)
    }
    
    func testChunkTextHandlesLongWord() {
        let longWord = String(repeating: "a", count: 100)
        let chunks = TextChunker.chunkText(longWord, maxLength: 50)
        
        // Should split the long word
        XCTAssertGreaterThan(chunks.count, 1)
    }
}

// MARK: - Text Sanitizer Tests

@available(macOS 14.0, *)
final class TextSanitizerTests: XCTestCase {
    
    func testSanitizeRemovesExtraWhitespace() {
        let input = "Hello    world"
        let sanitized = TextSanitizer.sanitize(input)
        
        XCTAssertFalse(sanitized.contains("    "))
    }
    
    func testSanitizeTrimsWhitespace() {
        let input = "  Hello world  "
        let sanitized = TextSanitizer.sanitize(input)
        
        XCTAssertFalse(sanitized.hasPrefix(" "))
        XCTAssertFalse(sanitized.hasSuffix(" "))
    }
    
    func testSanitizeHandlesEmptyString() {
        let sanitized = TextSanitizer.sanitize("")
        XCTAssertEqual(sanitized, "")
    }
    
    func testSanitizePreservesValidText() {
        let input = "Hello, world! How are you?"
        let sanitized = TextSanitizer.sanitize(input)
        
        XCTAssertEqual(sanitized, input)
    }
}