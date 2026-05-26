import Foundation

/// Priority bucket for `TaskItem`. Stored on `TaskItem.priorityRaw` as `Int` because
/// SwiftData + CloudKit mirroring rejects enum-typed model properties.
public enum TaskPriority: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
}
