import Foundation

/// Stable identifier for an `AIProvider`. Raw values are persisted to `AIUsageLog`
/// and surfaced in UI badges, so these MUST NOT be renamed without a migration.
public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case appleIntelligence
    case whisperKit
    /// On-device MLX language model (no consent, no network required).
    case mlx
}
