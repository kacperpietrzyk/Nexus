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
}
