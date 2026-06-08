import Foundation

/// Lifecycle state machine for a `Project` (Projects tier, spec §4.1). Stored on
/// `Project.statusRaw` as `String` because SwiftData + CloudKit mirroring rejects
/// enum-typed model properties (mirrors `TaskStatus`).
///
/// Raw values are CloudKit-bound and MUST NEVER be renamed without a migration.
/// Note the British spelling `cancelled` (two `l`s) — deliberately distinct from
/// `WorkflowState.canceled` (one `l`); these are separate persisted vocabularies.
public enum ProjectStatus: String, Codable, Sendable, CaseIterable {
    /// Idea, not yet scheduled.
    case backlog
    /// Scheduled, not yet started.
    case planned
    /// In progress.
    case active
    /// Wrapping up / under review.
    case inReview
    case completed
    case cancelled
}
