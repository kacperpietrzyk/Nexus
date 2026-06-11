import Foundation

/// The kind of one `ActivityEntry` audit-log event (Tranche 2, Linear L3 /
/// Todoist T6). Stable raw values — they land in CloudKit and must NEVER be
/// renamed after introduction (pinned by test, like `NoteRole`).
public enum ActivityEventKind: String, Codable, Sendable, CaseIterable {
    case created
    case completed
    case reopened
    case workflowChanged
    case projectMoved
    case priorityChanged
    case dueChanged
    /// Cycle assignment is an audited move (Plan C wires the writer).
    case cycleChanged
    /// Soft-delete is a user-visible lifecycle event.
    case deleted
}
