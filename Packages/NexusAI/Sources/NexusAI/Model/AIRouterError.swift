import Foundation

/// Typed errors thrown by `AIRouter.route(_:)` or by provider stubs.
///
/// Discriminating these in callers lets the UI show targeted prompts.
public enum AIRouterError: Error, Equatable, Sendable {
    /// No provider in the registered set could fulfil this request after applying
    /// platform filter + capability filter + consent + quota gates. Caller should
    /// surface a generic "AI unavailable" message.
    case noProviderAvailable

    /// Cloud call required but user has not granted consent for that provider yet.
    case consentRequired(ProviderID)

    /// Cloud call required and consented, but quota for the day is exhausted.
    case quotaExceeded(ProviderID)

    /// A selected provider accepted the request but failed while looking up or
    /// executing the provider-side operation. This is not a routing miss.
    case requestFailed(ProviderID, String)

    /// Request asked for a capability no available provider advertises (e.g. longContext
    /// while `connectivity == .offlineOnly`).
    case capabilityNotSupported(AICapability)

    /// The chosen provider is a Phase 0e stub. Phase 1+ replaces the stub with a real
    /// implementation. Tests exercising routing decisions never hit this — they use
    /// `FakeAIProvider`. Production code reaching this is a bug in the composition root.
    case providerNotImplemented(ProviderID)
}

extension AIRouterError: LocalizedError {
    /// Human-facing message. Without this, surfaces that show
    /// `error.localizedDescription` (e.g. the agent turn's error banner) print
    /// the generic "operation couldn't be completed" string instead of
    /// something the user can act on.
    public var errorDescription: String? {
        switch self {
        case .noProviderAvailable:
            return "No AI model is available right now. Check Settings or try again later."
        case .consentRequired(let provider):
            return "Using \(provider.displayName) needs your permission. Enable it in Settings."
        case .quotaExceeded(let provider):
            return "You've reached today's \(provider.displayName) usage limit. Try again tomorrow."
        case .requestFailed(_, let message):
            return message
        case .capabilityNotSupported:
            return "This request isn't supported by the available AI models right now."
        case .providerNotImplemented(let provider):
            return "\(provider.displayName) isn't available yet."
        }
    }
}
