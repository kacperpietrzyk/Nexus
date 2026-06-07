import Foundation

/// Provenance of a `TaskItem.estimatedDurationSeconds`. Stored on
/// `TaskItem.durationSourceRaw` as `String?` (SwiftData + CloudKit mirroring
/// rejects enum-typed model properties). Drives the duration-estimate override
/// cascade (spec §5): an `explicit` value always wins and feeds the history
/// corpus; an `estimated` value is the heuristic guess and may be refined.
///
/// Stable raw values — these land in CloudKit and must NEVER be renamed without
/// a migration.
public enum DurationSource: String, Codable, Sendable, CaseIterable {
    /// Parsed from natural language by `DurationExtractor` or set/overridden by
    /// the user. Authoritative; confidence 1.0.
    case explicit
    /// Produced by the heuristic `DurationEstimator`. Refinable.
    case estimated
}
