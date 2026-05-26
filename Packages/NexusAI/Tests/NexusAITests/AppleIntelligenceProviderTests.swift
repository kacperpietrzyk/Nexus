import Testing

@testable import NexusAI

@Test func appleIntelligence_identity() {
    let provider = AppleIntelligenceProvider()
    #expect(provider.id == .appleIntelligence)
    #expect(provider.sendsDataExternally == false)
    #expect(provider.requiresNetwork == false)
    #expect(provider.supportsImageAttachments == false)
    #expect(provider.isAvailableOnThisPlatform)
}

@Test func appleIntelligence_capabilities() {
    let provider = AppleIntelligenceProvider()
    #expect(provider.capabilities.contains(.generate))
    #expect(provider.capabilities.contains(.embed))
    // Foundation Models has ~4-8K context → long-context escalates to cloud.
    #expect(provider.capabilities.contains(.longContext) == false)
    // Transcription belongs to WhisperKit (separate on-device provider).
    #expect(provider.capabilities.contains(.transcribe) == false)
}

@Test func appleIntelligence_embedText_returnsVector() async throws {
    let provider = AppleIntelligenceProvider()
    let vector = try await provider.embed("vec")

    #expect(!vector.isEmpty)
    #expect(vector.count == AppleIntelligenceEmbeddingImpl.vectorDimension)
}

@Test func appleIntelligence_embedRequest_returnsVectorFieldWithoutTextPayload() async throws {
    let provider = AppleIntelligenceProvider()
    let response = try await provider.embed(.test(prompt: "vec", capability: .embed))
    let vector = try #require(response.embeddingVector)

    #expect(response.providerUsed == .appleIntelligence)
    #expect(response.text.isEmpty)
    #expect(!vector.isEmpty)
    #expect(vector.count == AppleIntelligenceEmbeddingImpl.vectorDimension)
}

@Test func appleIntelligence_routerEmbed_returnsVectorFieldWithoutTextPayload() async throws {
    let router = AIRouter(
        providers: [AppleIntelligenceProvider()],
        consent: InMemoryConsentStore(),
        quota: InMemoryQuotaTracker(),
        secrets: InMemorySecretStore()
    )
    let response = try await router.route(.test(prompt: "vec", capability: .embed))
    let vector = try #require(response.embeddingVector)

    #expect(response.providerUsed == .appleIntelligence)
    #expect(response.text.isEmpty)
    #expect(!vector.isEmpty)
    #expect(vector.count == AppleIntelligenceEmbeddingImpl.vectorDimension)
}

@Test func appleIntelligence_transcribe_throwsNotImplemented() async {
    let provider = AppleIntelligenceProvider()
    await #expect(throws: AIRouterError.providerNotImplemented(.appleIntelligence)) {
        try await provider.transcribe(.test(prompt: "audio", capability: .transcribe))
    }
}

@Test func appleIntelligence_generateReportsRequestFailureWhenFoundationModelsUnavailable() async {
    let provider = AppleIntelligenceProvider(isFoundationModelAvailable: { false })
    await #expect(
        throws: AIRouterError.requestFailed(
            .appleIntelligence,
            "Foundation Models generation is unavailable on this device."
        )
    ) {
        try await provider.generate(.test(prompt: "hi", capability: .generate))
    }
}

@Test(
    .disabled(
        if: !AppleIntelligenceProvider.isModelAvailable,
        "Apple Intelligence not available on this device/CI"
    )
)
func appleIntelligence_generate_real() async throws {
    let provider = AppleIntelligenceProvider()
    let response = try await provider.generate(
        .test(prompt: "Reply with: pong", capability: .generate)
    )
    #expect(response.providerUsed == .appleIntelligence)
    #expect(response.text.isEmpty == false)
}

// MARK: - Fixtures

extension AIRequest {
    fileprivate static func test(
        prompt: String,
        capability: AICapability
    ) -> AIRequest {
        AIRequest(prompt: prompt, capability: capability)
    }
}
