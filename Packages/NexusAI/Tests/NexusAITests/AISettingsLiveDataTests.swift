import Foundation
import NaturalLanguage
import Testing

@testable import NexusAI

@Suite("AISettingsLiveData")
@MainActor
struct AISettingsLiveDataTests {

    @Test("availability reflects AppleIntelligenceProvider.isModelAvailable")
    func availabilityMatchesProvider() {
        let data = AISettingsLiveData(router: nil)
        let expected: AvailabilityState =
            AppleIntelligenceProvider.isModelAvailable
            ? .available
            : .unavailable(reason: .modelNotAvailable)
        #expect(data.appleIntelligenceAvailability == expected)
    }

    @Test("local provider status is initialized")
    func localProviderStatusInitialized() {
        let data = AISettingsLiveData(router: nil)
        #expect(data.embeddingAvailability == expectedEmbeddingAvailability)
        #expect(data.whisperKitAvailability == expectedWhisperKitAvailability)
    }

    @Test("embedding availability matches Agent semantic indexing contract")
    func embeddingAvailabilityMatchesAgentSemanticIndexingContract() {
        #expect(
            AISettingsLiveData.hasAgentSemanticIndexEmbedding
                == (NLEmbedding.sentenceEmbedding(for: .english)?.dimension == 512)
        )
    }

    @Test("refresh with nil router is a no-op")
    func refreshWithNilRouter() async {
        let data = AISettingsLiveData(router: nil)
        await data.refresh()
        #expect(data.embeddingAvailability == expectedEmbeddingAvailability)
        #expect(data.whisperKitAvailability == expectedWhisperKitAvailability)
    }

    @Test("refresh ignores cloud quota readouts")
    func refreshIgnoresQuotaReadouts() async {
        let quota = InMemoryQuotaTracker(
            dailyTokenLimit: [
                .appleIntelligence: 10,
                .whisperKit: 20,
            ]
        )
        let router = AIRouter(
            providers: [],
            consent: InMemoryConsentStore(),
            quota: quota,
            secrets: InMemorySecretStore()
        )
        let data = AISettingsLiveData(router: router)

        await data.refresh()

        _ = data.appleIntelligenceAvailability
        #expect(data.embeddingAvailability == expectedEmbeddingAvailability)
        #expect(data.whisperKitAvailability == expectedWhisperKitAvailability)
    }

    private var expectedEmbeddingAvailability: AvailabilityState {
        NLEmbedding.sentenceEmbedding(for: .english)?.dimension == 512
            ? .available
            : .unavailable(reason: .modelNotAvailable)
    }

    private var expectedWhisperKitAvailability: AvailabilityState {
        WhisperKitProvider().isAvailableOnThisPlatform
            ? .available
            : .unavailable(reason: .modelNotAvailable)
    }
}
