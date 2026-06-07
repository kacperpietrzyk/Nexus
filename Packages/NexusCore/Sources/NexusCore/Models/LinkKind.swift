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
}
