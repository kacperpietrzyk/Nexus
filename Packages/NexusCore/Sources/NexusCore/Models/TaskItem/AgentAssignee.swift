import Foundation

/// Agent a `TaskItem` is assigned to (Projects tier, spec §4.5 / §8). Stored as
/// `String?` on `TaskItem.assignedAgent`; **`nil` = self** (the user).
///
/// Pure metadata: assignment NEVER affects scheduling or visibility (invariant
/// I8) — it only drives a filter and the MCP agent-queue exposure. Extensible:
/// add cases as agents come online; raw values are CloudKit-bound and MUST NEVER
/// be renamed without a migration.
public enum AgentAssignee: String, Codable, Sendable, CaseIterable {
    case codex
    case claude
}
