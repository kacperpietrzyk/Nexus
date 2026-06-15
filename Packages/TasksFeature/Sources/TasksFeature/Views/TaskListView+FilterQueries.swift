import Foundation
import NexusCore
import SwiftData

// Filter-specific fetch helpers, split out of TaskListView.swift to keep it
// under the file-length budget (the +Refinement precedent).
extension TaskListView {
    @MainActor
    static func savedFilterTasks(
        filterID: UUID,
        now: Date,
        modelContext: ModelContext
    ) throws -> [TaskItem] {
        let repository = SavedFilterRepository(context: modelContext, now: { now })
        guard let filter = try repository.find(filterID) else {
            throw SavedFilterTaskListError.missing
        }

        do {
            return rootTasks(from: try repository.apply(filter, now: now))
        } catch is DecodingError {
            throw SavedFilterTaskListError.corrupt
        }
    }

    /// Cycle-filtered list (Tranche 2 Plan C): live, non-template tasks of the
    /// cycle via `CycleRepository.tasks(in:)`, reduced to root tasks like every
    /// other filter funnel.
    @MainActor
    static func cycleTasks(cycleID: UUID, modelContext: ModelContext) throws -> [TaskItem] {
        rootTasks(from: try CycleRepository(context: modelContext).tasks(in: cycleID))
    }

    /// Templates management list (Tranche 2 Plan D): root templates via the
    /// `TaskTemplateQuery` funnel shared with the capture picker.
    @MainActor
    static func templateTasks(modelContext: ModelContext) throws -> [TaskItem] {
        try TaskTemplateQuery.rootTemplates(in: modelContext)
    }

    @MainActor
    static func rootTasks(from tasks: [TaskItem]) -> [TaskItem] {
        // `.dedupedByID()` defends the list against the historical synced-store
        // duplication (one logical task materialized as two same-`id` rows under
        // different entity versions). This is the funnel for nearly every Tasks
        // filter, so deduping here keeps the visible list honest without any
        // destructive write. No-op on a clean store.
        SubtaskTreeDataSource.rootTasks(from: tasks).dedupedByID()
    }

    @MainActor
    static func tasks(status: TaskStatus?, modelContext: ModelContext) throws -> [TaskItem] {
        if let status {
            let rawStatus = status.rawValue
            let predicate = #Predicate<TaskItem> { task in
                task.deletedAt == nil && task.statusRaw == rawStatus && task.parentTaskID == nil
                    && task.isTemplate == false
            }
            let descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\TaskItem.dueAt, order: .forward),
                    SortDescriptor(\TaskItem.createdAt, order: .reverse),
                ]
            )
            return try modelContext.fetch(descriptor).dedupedByID()
        }

        let doneStatus = TaskStatus.done.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.statusRaw != doneStatus && task.parentTaskID == nil
                && task.isTemplate == false
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\TaskItem.dueAt, order: .forward),
                SortDescriptor(\TaskItem.createdAt, order: .reverse),
            ]
        )
        return try modelContext.fetch(descriptor).dedupedByID()
    }

    @MainActor
    static func projectTasks(
        projectID: UUID,
        sectionID: UUID?,
        modelContext: ModelContext
    ) throws -> [TaskItem] {
        if let sectionID {
            // isTemplate post-filters in memory — a fourth #Predicate conjunct
            // blows the type-checker budget (the backlogTasks precedent).
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.projectID == projectID
                        && task.sectionID == sectionID
                        && task.deletedAt == nil
                }
            )
            return rootTasks(from: try modelContext.fetch(descriptor).filter { !$0.isTemplate })
                .sorted(by: Self.assignmentOrder)
        }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.projectID == projectID && task.deletedAt == nil && task.isTemplate == false
            }
        )
        return rootTasks(from: try modelContext.fetch(descriptor)).sorted(by: Self.assignmentOrder)
    }

    static func assignmentOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.orderIndex, rhs.orderIndex) {
        case (let left?, let right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            return lhs.createdAt < rhs.createdAt
        }
    }

    @MainActor
    static func inboxTasks(now: Date, modelContext: ModelContext) throws -> [TaskItem] {
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let noDate = try TodayQuery()
            .noDate(excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let snoozedStatus = TaskStatus.snoozed.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil && task.statusRaw == snoozedStatus && task.parentTaskID == nil
                    && task.isTemplate == false
            },
            sortBy: [SortDescriptor(\TaskItem.snoozedUntil, order: .forward)]
        )
        let snoozed = try modelContext.fetch(descriptor)
            .filter { ($0.snoozedUntil ?? .distantPast) > now }
            .filter { task in
                guard let projectID = task.projectID else { return true }
                return !archivedProjectIDs.contains(projectID)
            }
        return (rootTasks(from: noDate) + snoozed).dedupedByID().sorted { lhs, rhs in
            switch (lhs.snoozedUntil, rhs.snoozedUntil) {
            case (let lhsDate?, let rhsDate?):
                return lhsDate < rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}
