import Testing

@testable import NexusAI

private func makeRouter(
    apple: FakeAIProvider? = FakeAIProvider(
        id: .appleIntelligence,
        capabilities: [.generate, .embed],
        sendsDataExternally: false,
        requiresNetwork: false
    ),
    whisperKit: FakeAIProvider? = FakeAIProvider(
        id: .whisperKit,
        capabilities: [.transcribe],
        sendsDataExternally: false,
        requiresNetwork: false
    ),
    consent: any ConsentStore = InMemoryConsentStore(),
    quota: any QuotaTracker = InMemoryQuotaTracker(),
    secrets: any SecretStore = InMemorySecretStore()
) -> AIRouter {
    let providers = [apple, whisperKit].compactMap { $0 as (any AIProvider)? }
    return AIRouter(providers: providers, consent: consent, quota: quota, secrets: secrets)
}

@Test func r1_offlineGenerate_picksAppleIntelligence() async throws {
    let router = makeRouter()
    let response = try await router.route(AIRequest(prompt: "hi", capability: .generate))
    #expect(response.providerUsed == .appleIntelligence)
}

@Test func r2_cloudAllowed_butOnDeviceCapable_picksAppleFirst() async throws {
    let router = makeRouter()
    let response = try await router.route(
        AIRequest(
            prompt: "hi",
            capability: .generate,
            connectivity: .cloudAllowed
        ))
    #expect(response.providerUsed == .appleIntelligence)
}

@Test func onDeviceGenerate_skipsProviderNotReadyForGenerate_picksReadyFallback() async throws {
    // Apple Intelligence present (so `.embed` still routes) but NOT ready to `.generate`
    // (Foundation Models disabled). A loaded MLX-like on-device provider IS ready to generate.
    let apple = FakeAIProvider(
        id: .appleIntelligence,
        capabilities: [.generate, .embed],
        sendsDataExternally: false,
        requiresNetwork: false,
        unreadyCapabilities: [.generate]
    )
    let mlx = FakeAIProvider(
        id: .mlx,
        capabilities: [.generate],
        sendsDataExternally: false,
        requiresNetwork: false
    )
    let router = AIRouter(
        providers: [apple, mlx],
        consent: InMemoryConsentStore(),
        quota: InMemoryQuotaTracker(),
        secrets: InMemorySecretStore()
    )

    // `.generate` must skip the not-ready Apple provider and pick the loaded MLX model —
    // before the fix the router picked Apple (first + isAvailableOnThisPlatform) and dead-ended.
    let gen = try await router.route(AIRequest(prompt: "hi", capability: .generate))
    #expect(gen.providerUsed == .mlx)
    #expect(apple.generateCallCount == 0)

    // `.embed` still routes to Apple Intelligence (NaturalLanguage embeddings stay available).
    let emb = try await router.route(AIRequest(prompt: "hi", capability: .embed))
    #expect(emb.providerUsed == .appleIntelligence)
}

@Test func onDeviceGenerate_prefersReadyLocalModelOverAppleIntelligence() async throws {
    // Composition (`AIComposition`) orders the loaded MLX chat model BEFORE
    // Apple Intelligence so an assigned local model serves `.generate` — Apple
    // FM's on-device guardrail false-positives on benign non-English prompts,
    // and the user's downloaded model should win. With both ready, the router's
    // `onDevice.first` pick must select MLX. Guards against reverting the order.
    let mlx = FakeAIProvider(
        id: .mlx,
        capabilities: [.generate],
        sendsDataExternally: false,
        requiresNetwork: false
    )
    let apple = FakeAIProvider(
        id: .appleIntelligence,
        capabilities: [.generate, .embed],
        sendsDataExternally: false,
        requiresNetwork: false
    )
    let router = AIRouter(
        providers: [mlx, apple],
        consent: InMemoryConsentStore(),
        quota: InMemoryQuotaTracker(),
        secrets: InMemorySecretStore()
    )

    let gen = try await router.route(AIRequest(prompt: "hi", capability: .generate))
    #expect(gen.providerUsed == .mlx)
    #expect(apple.generateCallCount == 0)

    // `.embed` is unaffected: MLX chat advertises only `.generate`, so embed
    // still resolves to Apple Intelligence.
    let emb = try await router.route(AIRequest(prompt: "hi", capability: .embed))
    #expect(emb.providerUsed == .appleIntelligence)
}

@Test func imageAttachmentsHaveNoLocalOnlyProvider() async {
    let router = makeRouter()

    await #expect(throws: AIRouterError.noProviderAvailable) {
        try await router.route(
            AIRequest(
                prompt: "what is in this image?",
                capability: .generate,
                connectivity: .cloudAllowed,
                attachments: ["data:image/png;base64,cG5n"]
            )
        )
    }
}

@Test func imageAttachmentsRouteToLocalVisionCapableProviderWithoutCloudGates() async throws {
    let localVision = FakeAIProvider(
        id: .whisperKit,
        capabilities: [.generate],
        sendsDataExternally: false,
        requiresNetwork: false,
        supportsImageAttachments: true
    )
    let router = makeRouter(apple: nil, whisperKit: localVision)

    #expect(router.hasImageProvider)

    let response = try await router.route(
        AIRequest(
            prompt: "what is in this image?",
            capability: .generate,
            connectivity: .offlineOnly,
            attachments: ["data:image/png;base64,cG5n"]
        )
    )

    #expect(response.providerUsed == .whisperKit)
    #expect(localVision.generateCallCount == 1)
}

@Test func r3_longContextNeeded_cloudAllowed_throwsCapabilityNotSupported() async {
    let router = makeRouter()
    await #expect(throws: AIRouterError.capabilityNotSupported(.longContext)) {
        try await router.route(
            AIRequest(
                prompt: "long",
                capability: .longContext,
                connectivity: .cloudAllowed
            ))
    }
}

@Test func r4_longContextNeeded_offlineOnly_throwsCapabilityNotSupported() async {
    let router = makeRouter()
    await #expect(throws: AIRouterError.capabilityNotSupported(.longContext)) {
        try await router.route(AIRequest(prompt: "long", capability: .longContext))
    }
}

@Test func noProvider_advertisesCapability_throwsCapabilityNotSupported() async {
    let apple = FakeAIProvider(
        id: .appleIntelligence,
        capabilities: [.generate, .embed],
        sendsDataExternally: false,
        requiresNetwork: false
    )
    let whisperKit = FakeAIProvider(
        id: .whisperKit,
        capabilities: [.generate],
        sendsDataExternally: false,
        requiresNetwork: false
    )
    let router = makeRouter(apple: apple, whisperKit: whisperKit)

    await #expect(throws: AIRouterError.capabilityNotSupported(.transcribe)) {
        try await router.route(
            AIRequest(
                prompt: "audio",
                capability: .transcribe,
                connectivity: .cloudAllowed
            ))
    }
}

@Test func hasAvailableProvider_respectsTranscribeRoutingAvailability() async {
    let offlineTranscriber = FakeAIProvider(
        id: .whisperKit,
        capabilities: [.transcribe],
        sendsDataExternally: false,
        requiresNetwork: false
    )
    let unavailableOfflineTranscriber = FakeAIProvider(
        id: .whisperKit,
        capabilities: [.transcribe],
        sendsDataExternally: false,
        requiresNetwork: false,
        isAvailableOnThisPlatform: false
    )

    let availableRouter = makeRouter(apple: nil, whisperKit: offlineTranscriber)
    #expect(await availableRouter.hasAvailableProvider(for: AIRequest(prompt: "", capability: .transcribe)))

    let unavailableRouter = makeRouter(apple: nil, whisperKit: unavailableOfflineTranscriber)
    #expect(await unavailableRouter.hasAvailableProvider(for: AIRequest(prompt: "", capability: .transcribe)) == false)
}
