import Foundation
import SwiftData

/// Query shape for task buckets: a storage-side predicate, an in-memory post-filter,
/// storage-side sort descriptors, and an optional in-memory comparator applied last.
///
/// The `comparator` exists for orderings that storage-side `SortDescriptor`s cannot
/// express — notably "respect a persisted manual `orderIndex` when present, otherwise
/// fall back to another field". It runs after the fetch + `postFilter`, so the
/// storage `sort` still provides a stable, deterministic input order.
public struct TaskBucket: Sendable {
    public let predicate: Predicate<TaskItem>
    public let postFilter: @Sendable (TaskItem) -> Bool
    public let sort: [SortDescriptor<TaskItem>]
    public let comparator: (@Sendable (TaskItem, TaskItem) -> Bool)?

    public init(
        predicate: Predicate<TaskItem>,
        postFilter: @escaping @Sendable (TaskItem) -> Bool = { _ in true },
        sort: [SortDescriptor<TaskItem>] = [],
        comparator: (@Sendable (TaskItem, TaskItem) -> Bool)? = nil
    ) {
        self.predicate = predicate
        self.postFilter = postFilter
        self.sort = sort
        self.comparator = comparator
    }

    @MainActor
    public func apply(in context: ModelContext) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: predicate, sortBy: sort)
        let filtered = try context.fetch(descriptor).filter(postFilter)
        guard let comparator else { return filtered }
        return filtered.sorted(by: comparator)
    }
}
