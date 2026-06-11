import Foundation

/// Audit-event diff capture for `update(_:mutations:)` (Tranche 2 Plan B,
/// spec §4.1). Split out of `TaskItemRepository.swift` to keep that file under
/// the 600-line budget — the Workflow/Subtasks extension pattern.
@MainActor
extension TaskItemRepository {
    /// Pre-`mutations` snapshot of the audited axes. Captured the same way
    /// `update` already snapshots `recurrenceRule` for spawn regeneration.
    struct ActivityFieldSnapshot {
        let priorityRaw: Int
        let dueAt: Date?
        let projectID: UUID?
        let cycleID: UUID?

        init(of task: TaskItem) {
            priorityRaw = task.priorityRaw
            dueAt = task.dueAt
            projectID = task.projectID
            cycleID = task.cycleID
        }
    }

    /// `projectMoved` hook for `assign(_:toProject:section:)`. Skip-when-
    /// unchanged compares `projectID` only — a section-only move within the
    /// same project is not a `projectMoved` (spec §4.1).
    func recordProjectMove(on task: TaskItem, from oldProjectID: UUID?) {
        guard oldProjectID != task.projectID else { return }
        activity.recordChange(
            .projectMoved, itemID: task.id, itemKind: .task,
            old: oldProjectID?.uuidString, new: task.projectID?.uuidString
        )
    }

    /// Emits one entry per changed axis (priorityChanged / dueChanged /
    /// projectMoved / cycleChanged). Called before the host save so every
    /// entry rides it (I-B1).
    func recordFieldChanges(on task: TaskItem, since old: ActivityFieldSnapshot) {
        if old.priorityRaw != task.priorityRaw {
            activity.recordChange(
                .priorityChanged, itemID: task.id, itemKind: .task,
                old: String(old.priorityRaw), new: String(task.priorityRaw)
            )
        }
        if old.dueAt != task.dueAt {
            activity.recordChange(
                .dueChanged, itemID: task.id, itemKind: .task,
                old: ActivityChangePayload.dateString(old.dueAt),
                new: ActivityChangePayload.dateString(task.dueAt)
            )
        }
        if old.projectID != task.projectID {
            activity.recordChange(
                .projectMoved, itemID: task.id, itemKind: .task,
                old: old.projectID?.uuidString, new: task.projectID?.uuidString
            )
        }
        if old.cycleID != task.cycleID {
            activity.recordChange(
                .cycleChanged, itemID: task.id, itemKind: .task,
                old: old.cycleID?.uuidString, new: task.cycleID?.uuidString
            )
        }
    }
}
