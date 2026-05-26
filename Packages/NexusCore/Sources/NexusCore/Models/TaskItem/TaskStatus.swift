import Foundation

/// Lifecycle state of a `TaskItem`. Stored on `TaskItem.statusRaw` as `String` because
/// SwiftData + CloudKit mirroring rejects enum-typed model properties.
public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case open
    case done
    case snoozed
}
