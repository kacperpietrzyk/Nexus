import Foundation

/// Edge label on `Link`. Stored as `String` raw value on CloudKit — never rename without migration.
public enum LinkKind: String, Codable, Sendable, CaseIterable {
    case mentions
    case actionItem
    case blocks
    case child
    case source
    case attachment
}
