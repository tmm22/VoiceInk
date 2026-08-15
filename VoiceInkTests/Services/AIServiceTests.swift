import XCTest
@testable import VoiceInk

@available(macOS 14.0, *)
@MainActor
final class AIServiceTests: XCTestCase {
    func testOpenAIModelCatalogIncludesLatestVariants() {
        let models = AIProvider.openAI.availableModels

        XCTAssertEqual(AIProvider.openAI.defaultModel, "gpt-5.6-luna")
        XCTAssertTrue(models.contains("gpt-5.6-luna"))
        XCTAssertTrue(models.contains("gpt-5.6-terra"))
        XCTAssertTrue(models.contains("gpt-5.6-sol"))
        XCTAssertTrue(models.contains("gpt-5.5"))
        XCTAssertTrue(models.contains("gpt-5.4"))
        XCTAssertTrue(models.contains("gpt-5.4-mini"))
        XCTAssertTrue(models.contains("gpt-5.4-nano"))
        XCTAssertTrue(models.contains("gpt-4.1"))
        XCTAssertLessThan(
            models.firstIndex(of: "gpt-5.6-luna") ?? Int.max,
            models.firstIndex(of: "gpt-5.5") ?? Int.max
        )
    }

    func testReasoningDefaultsMatchProviderCapabilities() {
        XCTAssertEqual(
            ReasoningConfig.getReasoningParameter(for: .openAI, modelName: "gpt-5.6-luna"),
            "none"
        )
        XCTAssertEqual(
            ReasoningConfig.getReasoningParameter(for: .cerebras, modelName: "gpt-oss-120b"),
            "low"
        )
        XCTAssertEqual(
            ReasoningConfig.getReasoningParameter(for: .groq, modelName: "openai/gpt-oss-20b"),
            "low"
        )
        XCTAssertNil(
            ReasoningConfig.getReasoningParameter(for: .openAI, modelName: "gpt-4.1")
        )
    }

    func testLocalProvidersDoNotRequireAPIKeys() {
        XCTAssertFalse(AIProvider.ollama.requiresAPIKey)
        XCTAssertFalse(AIProvider.localCLI.requiresAPIKey)
        XCTAssertFalse(AIProvider.voiceInkRefine.requiresAPIKey)
    }
}
