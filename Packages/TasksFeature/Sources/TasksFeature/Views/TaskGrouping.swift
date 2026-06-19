import Foundation
import NexusCore

/// User-selectable sectioning for the flat task filters (`.all`/`.upcoming`/
/// `.inbox`). `.none` keeps the current flat list verbatim. Persisted across
/// launches via `NexusPreferences.Keys.taskListGroupBy`. Orthogonal to the
/// `.today` semantic buckets, which are unaffected.
public enum TaskGroupBy: String, CaseIterable, Sendable {
    case none
    case project
    case date
    case priority

    public var title: String {
        switch self {
        case .none: return "Group"
        case .project: return "Project"
        case .date: return "Date"
        case .priority: return "Priority"
        }
    }
}
