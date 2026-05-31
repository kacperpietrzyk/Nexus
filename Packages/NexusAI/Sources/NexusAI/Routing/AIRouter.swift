import Foundation

/// Single entry point for AI requests in the app. **Actor** — AI work is background;
/// callers don't need main-actor isolation.
///
/// Selection algorithm (matches Routing decision matrix in plan 0e):
///
/// 1. Filter providers by `isAvailableOnThisPlatform`.
/// 2. Filter by capability — provider must advertise `request.capability`.
/// 3. If attachments are present, keep only image-capable providers.
/// 4. Prefer on-device providers (`requiresNetwork == false`) first.
/// 5. If on-device providers are insufficient (none survived) and `request.allowsCloud`,
///    pick a cloud provider.
/// 6. Iterate cloud candidates in input order; cascade on consent/quota miss.
///    First candidate passing both gates wins. If every candidate fails, throw the
///    LAST candidate's gate error (most specific reason for the caller to act on).
///    Cascade applies only to **selection**: once a provider is picked, an error
///    thrown by `invoke` propagates to the caller (no router-level re-routing).
///    See spec §6.2 for the cascade-vs-short-circuit rule.
/// 7. If everything filters out: `.capabilityNotSupported` (when capability was the
///    blocker) or `.noProviderAvailable` (otherwise).
public actor AIRouter {
    private let providers: [any AIProvider]
    private let consent: any ConsentStore
    private let quota: any QuotaTracker
    private let secrets: any SecretStore
    public nonisolated let hasImageProvider: Bool

    public init(
        providers: [any AIProvider],
        consent: any ConsentStore,
        quota: any QuotaTracker,
        secrets: any SecretStore
    ) {
        self.providers = providers
        self.consent = consent
        self.quota = quota
        self.secrets = secrets
        self.hasImageProvider = providers.contains {
            $0.isAvailableOnThisPlatform
                && $0.capabilities.contains(.generate)
                && $0.supportsImageAttachments
        }
    }

    public func route(_ request: AIRequest) async throws -> AIResponse {
        let provider = try await selectProvider(for: request)
        return try await invoke(provider, with: request)
    }

    public func hasAvailableProvider(for request: AIRequest) async -> Bool {
        do {
            _ = try await selectProvider(for: request)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Selection

    private func selectProvider(for request: AIRequest) async throws -> any AIProvider {
        // Step 1: platform filter.
        let platformOK = providers.filter { $0.isAvailableOnThisPlatform }

        // Step 2: capability filter.
        var candidates = platformOK.filter { $0.capabilities.contains(request.capability) }

        // If capability eliminated every otherwise-available provider, capability was the blocker.
        if candidates.isEmpty && !platformOK.isEmpty {
            throw AIRouterError.capabilityNotSupported(request.capability)
        }

        // Step 3: attachment filter. Image attachments may only route to
        // providers that explicitly advertise image support. Local image
        // providers route without cloud gating; network providers still pass
        // through consent and quota checks below.
        if !request.attachments.isEmpty {
            candidates = candidates.filter(\.supportsImageAttachments)
            guard !candidates.isEmpty else {
                throw AIRouterError.noProviderAvailable
            }
        }

        // Step 4: prefer on-device first — but only an on-device provider that is actually ready
        // to serve this capability. AppleIntelligence reports `isAvailableOnThisPlatform == true`
        // unconditionally (so `.embed` always routes), yet can only `.generate` when Foundation
        // Models is enabled; picking it blindly here would dead-end at invoke on devices without
        // Apple Intelligence instead of falling through to a loaded MLX model (or cloud).
        let onDevice = candidates.filter { !$0.requiresNetwork && $0.isReady(for: request.capability) }
        if let pick = onDevice.first {
            return pick
        }

        // Step 5: cloud only if explicitly allowed.
        guard request.allowsCloud else {
            throw AIRouterError.capabilityNotSupported(request.capability)
        }

        // Step 6: pick cloud candidate, gating on consent + quota.
        let cloudCandidates = candidates.filter { $0.requiresNetwork }

        guard !cloudCandidates.isEmpty else {
            throw AIRouterError.noProviderAvailable
        }

        // Cascade through cloud candidates, gating each on consent + quota.
        // First passing candidate wins; if all fail, surface the last failure.
        // Spec §6.2: cascade applies only to selection — `invoke` errors do NOT
        // trigger re-routing.
        var lastError: AIRouterError = .noProviderAvailable
        for candidate in cloudCandidates {
            do {
                return try await gateCloudCandidate(candidate)
            } catch let error as AIRouterError {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private func gateCloudCandidate(_ candidate: any AIProvider) async throws -> any AIProvider {
        guard await consent.hasConsent(for: candidate.id) else {
            throw AIRouterError.consentRequired(candidate.id)
        }

        let usage = await quota.usage(for: candidate.id)
        guard !usage.isExceeded else {
            throw AIRouterError.quotaExceeded(candidate.id)
        }

        return candidate
    }

    // MARK: - Invocation

    private func invoke(_ provider: any AIProvider, with request: AIRequest) async throws -> AIResponse {
        switch request.capability {
        case .generate, .longContext: return try await provider.generate(request)
        case .transcribe: return try await provider.transcribe(request)
        case .embed: return try await provider.embed(request)
        }
    }
}

extension AIRouter {
    /// Read-only quota snapshot for Settings UI. Delegates to the underlying
    /// `QuotaTracker`; provider-side caching is the tracker's responsibility.
    public func usage(for provider: ProviderID) async -> QuotaUsage {
        await quota.usage(for: provider)
    }

    /// Warms the production WhisperKit provider instance without routing a synthetic audio request.
    public func preloadWhisperKit() async throws {
        guard let provider = providers.first(where: { $0.id == .whisperKit }) as? WhisperKitProvider else {
            throw AIRouterError.noProviderAvailable
        }

        try await provider.preload()
    }

    /// Warms the on-device MLX chat provider so it survives the availability
    /// filter in `selectProvider`. This is the cycle-break entry point — it
    /// reaches the provider by concrete type, NOT by `id`: both `MLXProvider`
    /// and `MLXEmbedderProvider` have `id == .mlx`, so an `id`-keyed lookup
    /// (the `preloadWhisperKit` pattern) would be ambiguous and could warm the
    /// wrong engine.
    public func preloadMLXChat() async throws {
        guard let provider = providers.compactMap({ $0 as? MLXProvider }).first else {
            throw AIRouterError.noProviderAvailable
        }

        try await provider.preload()
    }

    /// Warms the on-device MLX embedder provider (search/RAG dependency).
    /// Same concrete-type disambiguation as `preloadMLXChat`.
    public func preloadMLXEmbedder() async throws {
        guard let provider = providers.compactMap({ $0 as? MLXEmbedderProvider }).first else {
            throw AIRouterError.noProviderAvailable
        }

        try await provider.preload()
    }

    /// In-process rebind of the MLX chat provider after a model assignment
    /// change (Welcome auto-assign / Settings re-assign). Drops the stale
    /// container and re-warms against the newly-assigned folder.
    public func reloadMLXChat() async throws {
        guard let provider = providers.compactMap({ $0 as? MLXProvider }).first else {
            throw AIRouterError.noProviderAvailable
        }

        try await provider.reload()
    }

    /// In-process rebind of the MLX embedder provider after an embedder
    /// assignment change.
    public func reloadMLXEmbedder() async throws {
        guard let provider = providers.compactMap({ $0 as? MLXEmbedderProvider }).first else {
            throw AIRouterError.noProviderAvailable
        }

        try await provider.reload()
    }
}
