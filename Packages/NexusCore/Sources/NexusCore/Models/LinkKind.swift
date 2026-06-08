import Foundation

/// Edge label on `Link`. Stored as `String` raw value on CloudKit — never rename without migration.
public enum LinkKind: String, Codable, Sendable, CaseIterable {
    case mentions
    case actionItem
    case blocks
    case child
    case source
    case attachment
    /// An embed-block in a Note transcludes another object (read-only preview).
    /// Semantically distinct from `mentions` — the renderer shows a live preview.
    case embed
    /// A todo-block in a Note "contains" a `TaskItem`. Dedicated edge — does NOT
    /// overload `child` (reserved for subtask/hierarchy).
    case containsTask
    /// A `TaskItem` is scheduled as a `ScheduledBlock` (task → block edge,
    /// Calendar module). Distinct from `child`/`containsTask`.
    case scheduledAs
    /// A task or project (`from`) carries a `Label` (`to`) — the many-to-many
    /// edge for the Projects-tier label graph (spec §4.4). Single-select per
    /// label group is enforced in `LabelRepository`, not on the edge.
    case labeled
    /// A `Meeting` (`from`) had a `Person` (`to`) as an attendee (People/Contacts
    /// module, spec §4.2): `Link(from:(.meeting, id), to:(.person, id), .attendee)`.
    /// Distinct from `.mentions` (task/note → person), which is the related/mentioned
    /// edge — never ownership/assignee (invariant I1).
    case attendee
}
