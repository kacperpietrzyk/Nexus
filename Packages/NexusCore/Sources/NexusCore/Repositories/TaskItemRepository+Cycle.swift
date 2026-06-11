import Foundation
import SwiftData

/// Cycle assignment (Tranche 2 Plan C). Split out of the main repository file
/// to keep it under the file-length budget — the Workflow/Subtasks extension
/// precedent.
extension TaskItemRepository {
    /// Assigns or clears a task's cycle. Mirrors `assign(_:toProject:)`:
    /// validates a non-nil target exists and is live, writes the raw pointer,
    /// bumps `updatedAt`, records a `cycleChanged` activity event (old/new
    /// payload, spec §4.1), saves, and pushes the watch snapshot. No-op (no
    /// save, no event) when the assignment is unchanged. The event is inserted
    /// BEFORE the save so it commits atomically with the mutation (I-B1).
    public func assignCycle(_ task: TaskItem, to cycleID: UUID?) throws {
        guard task.cycleID != cycleID else { return }
        if let cycleID {
            let descriptor = FetchDescriptor<Cycle>(
                predicate: #Predicate { cycle in cycle.id == cycleID && cycle.deletedAt == nil }
            )
            guard try context.fetch(descriptor).first != nil else {
                throw TaskItemRepositoryError.cycleNotFound(cycleID: cycleID)
            }
        }
        let oldCycleID = task.cycleID
        task.cycleID = cycleID
        task.updatedAt = now()
        activity.recordChange(
            .cycleChanged,
            itemID: task.id,
            itemKind: .task,
            old: oldCycleID?.uuidString,
            new: cycleID?.uuidString
        )
        try context.save()
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }
}
