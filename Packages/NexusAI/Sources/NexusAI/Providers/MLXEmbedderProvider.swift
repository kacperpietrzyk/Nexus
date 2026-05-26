import Foundation

/// On-device embedding provider backed by `MLXEmbedderEngine`.
///
/// `MLXEmbedderProvider` only advertises `.embed`. It is on-device (no consent,
/// no network) and produces one L2-normalized vector per request. It mirrors the
/// `MLXProvider` actor-isolation pattern: identity / capability metadata is
/// `nonisolated`, the engine is actor-isolated state, and availability is probed
/// through an injected `@Sendable` closure (thermal-degradation gating + simulator
/// detection upstream).
///
/// `generate` / `transcribe` throw `AIRouterError.providerNotImplemented(.mlx)` —
/// the same unsupported-capability convention `MLXProvider` / `WhisperKitProvider`
/// / `AppleIntelligenceProvider` use.
public actor MLXEmbedderProvider: AIProvider {
    public nonisolated let id: ProviderID = .mlx
    public nonisolated let capabilities: Set<AICapability> = [.embed]
    public nonisolated let sendsDataExternally: Bool = false
    public nonisolated let requiresNetwork: Bool = false
    public nonisolated let supportsImageAttachments: Bool = false

    public nonisolated var isAvailableOnThisPlatform: Bool { availabilityProbe() }

    private nonisolated let availabilityProbe: @Sendable () -> Bool
    private let engine: MLXEmbedderEngine

    public init(
        engine: MLXEmbedderEngine,
        availabilityProbe: @escaping @Sendable () -> Bool
    ) {
        self.engine = engine
        self.availabilityProbe = availabilityProbe
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.mlx)
    }

    public func transcribe(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.mlx)
    }

    public func embed(_ request: AIRequest) async throws -> AIResponse {
        // `request.prompt` is the context-complete carrier (consistent with
        // `MLXProvider.generate`); embedding produces no text + zero on-device
        // cost, and echoes `request.context` as citations for backlinks.
        let vector = try await engine.embed(text: request.prompt)
        return AIResponse(
            text: "",
            providerUsed: .mlx,
            citations: request.context,
            embeddingVector: vector,
            tokensUsed: .zero,
            costEstimateUSD: 0
        )
    }

    /// Warms the embedder container so `isAvailableOnThisPlatform` flips true
    /// without routing a synthetic embed request — the entry point that breaks
    /// the embedder availability/load cycle (search/RAG depend on it).
    public func preload() async throws {
        try await engine.preload()
    }

    /// In-process rebind after an embedder assignment change: drop the stale
    /// container (bumps the engine epoch and clears the lifecycle slot), then
    /// warm again against the dynamically re-resolved folder.
    public func reload() async throws {
        await engine.unload()
        try await engine.preload()
    }
}
