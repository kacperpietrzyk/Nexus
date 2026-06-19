import Foundation
import NexusCore

/// Pure ordering for the picker Grid (spec §2 WS-1): pinned first, then the
/// Active status group ahead of everything else, then most-recently-updated,
/// with name + id tie-breaks for deterministic output.
enum ProjectGridOrder {
    static func sorted(_ projects: [Project]) -> [Project] {
        projects.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            let lActive = lhs.status == .active
            let rActive = rhs.status == .active
            if lActive != rActive { return lActive }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
