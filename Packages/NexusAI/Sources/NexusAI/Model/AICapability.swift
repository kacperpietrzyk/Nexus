import Foundation

/// Capability requested by an `AIRequest` and advertised by an `AIProvider`.
///
/// `.longContext` is a marker capability used in routing: when an on-device provider
/// lacks it (Apple Intelligence ~8K context per spec §6.1), the router escalates to
/// cloud — but only if `request.allowsCloud == true`. See `AIRouter.route`.
public enum AICapability: String, Codable, Sendable, Hashable, CaseIterable {
    case generate
    case transcribe
    case embed
    case longContext
}
