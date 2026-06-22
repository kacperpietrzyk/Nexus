import Foundation
import SwiftData

// MARK: - Orphaned-task query (trust-gap surface)

extension TaskItemRepository {
    /// Returns live, non-template tasks whose `projectID` no longer resolves to a
    /// non-deleted project — the "trust gap" after bulk migrations where project
    /// shells are soft-deleted but their tasks remain. Implementation uses an
    /// in-code join because SwiftData `#Predicate` cannot express a cross-entity
    /// containment check without a relationship.
    ///
    /// Algorithm:
    /// 1. Fetch the UUID set of all non-deleted projects (O(projects)).
    /// 2. Fetch candidates: non-deleted, non-template tasks where `projectID != nil`.
    /// 3. Filter in memory: keep tasks whose `projectID ∉ liveProjectIDs`.
    public func orphanedTasks() throws -> [TaskItem] {
        let liveIDs = try liveProjectIDs()
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.projectID != nil && task.deletedAt == nil && task.isTemplate == false
            }
        )
        let candidates = try context.fetch(descriptor)
        return candidates.filter { task in
            guard let pid = task.projectID else { return false }
            return !liveIDs.contains(pid)
        }
    }

    /// ID set of every non-deleted project. Used by `tasks.list` to exclude
    /// orphaned tasks from the default open/done paths without a full fetch.
    public func liveProjectIDs() throws -> Set<UUID> {
        Set(
            try context.fetch(
                FetchDescriptor<Project>(
                    predicate: #Predicate { project in project.deletedAt == nil }
                )
            ).map(\.id)
        )
    }
}
