import Foundation
import SwiftData

@MainActor
extension TaskItemRepository {
    public func softDelete(_ task: TaskItem, cascade: Bool = true) throws {
        let stamp = now()
        var visited = Set<UUID>()
        var deletedTaskIDs = Set<UUID>()
        try softDelete(
            task,
            cascade: cascade,
            stamp: stamp,
            visited: &visited,
            deletedTaskIDs: &deletedTaskIDs
        )
        let commentRepository = CommentRepository(context: context)
        for deletedTaskID in deletedTaskIDs {
            try commentRepository.softDeleteAll(for: deletedTaskID, kind: .task)
        }
        try context.save()
        cancelNotificationsAndPushSnapshot(taskIDs: deletedTaskIDs)
    }

    /// Returns the open, non-soft-deleted direct children of `parent`. Use
    /// `allSubtasks(of:)` if you also need done or snoozed children.
    public func subtasks(of parent: TaskItem) throws -> [TaskItem] {
        try openSubtasks(parentID: parent.id)
    }

    /// Returns every non-soft-deleted direct child of `parent` regardless of
    /// status (open, snoozed, done). Internal lifecycle paths (cascade complete,
    /// cascade soft-delete) still go through `activeSubtasks` which mirrors this
    /// shape minus the public API contract.
    public func allSubtasks(of parent: TaskItem) throws -> [TaskItem] {
        try activeSubtasks(parentID: parent.id)
    }

    public func markDoneStrict(_ task: TaskItem) throws {
        let openCount = try openDirectSubtaskCount(parentID: task.id)
        guard openCount == 0 else {
            throw TaskItemRepositoryError.parentHasOpenSubtasks(parentID: task.id, openCount: openCount)
        }

        try markDone(task)
    }

    public func cascadeComplete(_ task: TaskItem) throws {
        let stamp = now()
        var visited = Set<UUID>()
        var sideEffects = TaskCompletionSideEffects()
        try cascadeComplete(task, stamp: stamp, visited: &visited, sideEffects: &sideEffects)
        guard sideEffects.isEmpty == false else { return }
        try context.save()
        dispatchCompletionSideEffects(sideEffects)
    }

    /// Cancels notifications for task IDs and tickles the snapshot pusher.
    /// Used by soft delete paths that do not schedule follow-up tasks.
    private func cancelNotificationsAndPushSnapshot(taskIDs: some Sequence<UUID>) {
        let ids = Array(Set(taskIDs))
        guard ids.isEmpty == false else { return }
        let notifier = notifications
        Task { @MainActor in
            for taskID in ids {
                await notifier.cancel(taskID: taskID)
            }
        }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    private func activeSubtasks(parentID: UUID) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.parentTaskID == parentID && task.deletedAt == nil
            }
        )
        return try context.fetch(descriptor).sorted(by: Self.assignmentOrder)
    }

    private func openSubtasks(parentID: UUID) throws -> [TaskItem] {
        let openRaw = TaskStatus.open.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.parentTaskID == parentID
                    && task.deletedAt == nil
                    && task.statusRaw == openRaw
            }
        )
        return try context.fetch(descriptor).sorted(by: Self.assignmentOrder)
    }

    private func openDirectSubtaskCount(parentID: UUID) throws -> Int {
        let doneRaw = TaskStatus.done.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.parentTaskID == parentID
                    && task.deletedAt == nil
                    && task.statusRaw != doneRaw
            }
        )
        return try context.fetchCount(descriptor)
    }

    private func cascadeComplete(
        _ task: TaskItem,
        stamp: Date,
        visited: inout Set<UUID>,
        sideEffects: inout TaskCompletionSideEffects
    ) throws {
        guard visited.insert(task.id).inserted else { return }

        try completeTask(task, stamp: stamp, sideEffects: &sideEffects)

        for child in try activeSubtasks(parentID: task.id) {
            try cascadeComplete(child, stamp: stamp, visited: &visited, sideEffects: &sideEffects)
        }
    }

    private func softDelete(
        _ task: TaskItem,
        cascade: Bool,
        stamp: Date,
        visited: inout Set<UUID>,
        deletedTaskIDs: inout Set<UUID>
    ) throws {
        guard visited.insert(task.id).inserted else { return }

        task.deletedAt = stamp
        task.updatedAt = stamp
        deletedTaskIDs.insert(task.id)

        guard cascade else { return }

        for child in try activeSubtasks(parentID: task.id) {
            try softDelete(
                child,
                cascade: true,
                stamp: stamp,
                visited: &visited,
                deletedTaskIDs: &deletedTaskIDs
            )
        }
    }
}
