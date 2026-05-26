import Foundation
import SwiftData

/// Query shape for task buckets: a storage-side predicate, an in-memory post-filter,
/// and storage-side sort descriptors.
public struct TaskBucket: Sendable {
    public let predicate: Predicate<TaskItem>
    public let postFilter: @Sendable (TaskItem) -> Bool
    public let sort: [SortDescriptor<TaskItem>]

    public init(
        predicate: Predicate<TaskItem>,
        postFilter: @escaping @Sendable (TaskItem) -> Bool = { _ in true },
        sort: [SortDescriptor<TaskItem>] = []
    ) {
        self.predicate = predicate
        self.postFilter = postFilter
        self.sort = sort
    }

    @MainActor
    public func apply(in context: ModelContext) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: predicate, sortBy: sort)
        return try context.fetch(descriptor).filter(postFilter)
    }
}
