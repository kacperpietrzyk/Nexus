import Foundation

/// Optional tracker state machine on a `TaskItem` (Projects tier, spec §4.2).
/// Stored as `String?` on `TaskItem.workflowStateRaw`.
///
/// **`nil` = a plain GTD task** (Inbox / personal): it does not participate in the
/// machine and runs purely on `status` (open/done/snoozed) exactly as before
/// (invariant I7). A non-nil `workflowState` deterministically drives `status`
/// per the reconciliation table (spec §5.1).
///
/// Raw values are CloudKit-bound and MUST NEVER be renamed without a migration.
/// Note the American spelling `canceled` (one `l`) — deliberately distinct from
/// `ProjectStatus.cancelled` (two `l`s).
public enum WorkflowState: String, Codable, Sendable, CaseIterable {
    case backlog
    case todo
    case inProgress
    case inReview
    case done
    case canceled
    case duplicate

    /// `canceled`/`duplicate` are terminal *closures* that are NOT counted as
    /// completed work (spec §5.2 I4): they force `status = .done` but never set
    /// `lastCompletedAt`, so completion-stats exclude them.
    public var isTerminalNonCompletion: Bool {
        switch self {
        case .canceled, .duplicate:
            return true
        case .backlog, .todo, .inProgress, .inReview, .done:
            return false
        }
    }

    /// The `TaskStatus` this workflow state forces (spec §5.1, one-directional
    /// `workflowState ⇒ status`). Snooze is orthogonal (I2) and handled by the
    /// repository, not encoded here.
    public var forcedStatus: TaskStatus {
        switch self {
        case .backlog, .todo, .inProgress, .inReview:
            return .open
        case .done, .canceled, .duplicate:
            return .done
        }
    }
}
