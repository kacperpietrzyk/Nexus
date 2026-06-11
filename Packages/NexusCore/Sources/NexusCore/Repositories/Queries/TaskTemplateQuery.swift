import Foundation
import SwiftData

/// The single funnel for template-management surfaces (Tranche 2 Plan D):
/// the Templates list (`TaskFilter.templates`), the capture-pane template
/// picker, and the detail-inspector instantiate affordance. Root templates
/// only — subtask templates render under their parent, never as picker rows.
public enum TaskTemplateQuery {
    @MainActor
    public static func rootTemplates(in context: ModelContext) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.isTemplate == true && task.deletedAt == nil && task.parentTaskID == nil
            },
            sortBy: [SortDescriptor(\TaskItem.title, order: .forward)]
        )
        // `.dedupedByID()` — same synced-store duplicate-id defense every
        // query-based read applies (see `TaskBucket.apply`).
        return try context.fetch(descriptor).dedupedByID()
    }
}
