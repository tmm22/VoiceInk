import Foundation
import XCTest
@testable import VoiceInk

/// Batch cloud transcription only builds the custom vocabulary for providers that send it.
final class CloudVocabularyRoutingTests: XCTestCase {
    /// Providers whose batch `transcribe` never reads `customVocabulary`.
    private let providersWithoutVocabulary: Set<ModelProvider> = [.groq, .openRouter]

    func testOnlyGroqAndOpenRouterOptOutOfTheVocabulary() {
        XCTAssertFalse(GroqProvider().usesCustomVocabulary)
        XCTAssertFalse(OpenRouterProvider().usesCustomVocabulary)

        for provider in CloudProviderRegistry.allProviders {
            XCTAssertEqual(
                provider.usesCustomVocabulary,
                !providersWithoutVocabulary.contains(provider.modelProvider),
                provider.providerKey
            )
        }
    }

    func testRegistryLookupReportsTheProvidersOwnAnswer() {
        // The flag is a protocol requirement, so it must dispatch through `any CloudProvider`.
        XCTAssertEqual(CloudProviderRegistry.provider(for: .groq)?.usesCustomVocabulary, false)
        XCTAssertEqual(CloudProviderRegistry.provider(for: .openRouter)?.usesCustomVocabulary, false)
        XCTAssertEqual(CloudProviderRegistry.provider(for: .deepgram)?.usesCustomVocabulary, true)
        XCTAssertEqual(CloudProviderRegistry.provider(for: .cartesia)?.usesCustomVocabulary, true)
    }

    func testVocabularyIsFetchedForEveryProviderExceptThoseThatNeverSendIt() {
        for provider in ModelProvider.allCases {
            let skipsFetch = provider == .custom || providersWithoutVocabulary.contains(provider)
            XCTAssertEqual(
                CloudTranscriptionService.needsCustomVocabulary(for: provider),
                !skipsFetch,
                provider.rawValue
            )
        }
    }

    func testCustomModelsSkipTheFetchBecauseTheirBranchNeverPassesIt() {
        XCTAssertFalse(CloudTranscriptionService.needsCustomVocabulary(for: .custom))
    }

    func testProvidersOutsideTheCloudRegistryKeepTheFetch() {
        for provider in [ModelProvider.whisper, .fluidAudio, .transcribeCpp, .nativeApple] {
            XCTAssertNil(CloudProviderRegistry.provider(for: provider))
            XCTAssertTrue(CloudTranscriptionService.needsCustomVocabulary(for: provider), provider.rawValue)
        }
    }
}
