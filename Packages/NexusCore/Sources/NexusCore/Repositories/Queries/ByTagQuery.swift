import Foundation
import SwiftData

/// Open tasks containing a given tag. Lookup is case-insensitive.
public struct ByTagQuery: Sendable {
    public init() {}

    public func tasks(withTag tag: String) -> TaskBucket {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let openStatus = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.statusRaw == openStatus
                && task.isTemplate == false
        }
        return TaskBucket(
            predicate: predicate,
            postFilter: { task in task.tags.contains(normalized) },
            sort: [SortDescriptor(\TaskItem.dueAt, order: .forward)]
        )
    }
}
