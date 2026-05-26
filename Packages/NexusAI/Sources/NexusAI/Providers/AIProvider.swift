import Foundation

/// Per spec §6.1 — uniform contract for every provider the router can pick.
///
/// All implementations are `Sendable`. Provider stubs in 0e are stateless `final class`es;
/// real implementations in later phases may hold authenticated session state inside an
/// `actor` and conform via that.
public protocol AIProvider: Sendable {
    /// Stable identifier (used in `AIResponse.providerUsed`, `AIUsageLog`, UI badges).
    var id: ProviderID { get }

    /// What this provider can do. Routing matches against `AIRequest.capability`.
    var capabilities: Set<AICapability> { get }

    /// `true` for any provider that uploads user data to a third party
    /// (everything except `appleIntelligence` + `whisperKit`).
    /// Used for transparency badges (spec §6.5) and consent gating.
    var sendsDataExternally: Bool { get }

    /// `true` if a call requires network connectivity.
    /// On-device providers (`appleIntelligence`, `whisperKit`) return `false`.
    var requiresNetwork: Bool { get }

    /// Platform-specific availability. Cloud providers may return `false` until their
    /// authenticated runtime is configured.
    var isAvailableOnThisPlatform: Bool { get }

    /// Explicit contract for providers that can accept image data URL attachments.
    /// Text-only cloud providers must leave this `false`; attachment routing uses
    /// it before any consented network call is allowed.
    var supportsImageAttachments: Bool { get }

    func generate(_ request: AIRequest) async throws -> AIResponse
    func transcribe(_ request: AIRequest) async throws -> AIResponse
    func embed(_ request: AIRequest) async throws -> AIResponse
}

extension AIProvider {
    public var supportsImageAttachments: Bool { false }
}
