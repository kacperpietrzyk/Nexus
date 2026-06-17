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
        // `.dedupedByID()` is the universal guard for query-based reads: on a
        // synced store a single logical task can be materialized as two same-`id`
        // rows (one under a stale entity version from an older migration), so a
        // raw fetch double-counts. Collapsing here keeps every facet that flows
        // through a `TaskBucket` — Today's embedded list, the brief counts, the
        // capture sheet — honest without a destructive write. No-op when clean.
        let filtered = try context.fetch(descriptor).dedupedByID().filter(postFilter)
        guard let comparator else { return filtered }
        return filtered.sorted(by: comparator)
    }

    /// One page of a windowed bucket fetch: the surviving (deduped, post-filtered)
    /// tasks for this raw window plus the cursor a caller advances to fetch the next
    /// page.
    ///
    /// `rawCursor` is the *raw* DB offset to resume from — it counts every row the
    /// storage fetch returned for this window, NOT just the rows that survived the
    /// in-memory `postFilter`/dedup. Advancing by the raw cursor (rather than by the
    /// number of surviving rows) is what keeps consecutive pages gap-free and
    /// overlap-free when a `postFilter` is present: the next page picks up exactly
    /// where the storage scan left off. `hasMore` is true iff the storage fetch
    /// returned a full `rawLimit` worth of rows (so another window may exist).
    public struct Page {
        public let items: [TaskItem]
        public let rawCursor: Int
        public let hasMore: Bool

        public init(items: [TaskItem], rawCursor: Int, hasMore: Bool) {
            self.items = items
            self.rawCursor = rawCursor
            self.hasMore = hasMore
        }
    }

    /// Fetches a single window of this bucket, DB-sorted, starting at the raw DB
    /// offset `rawOffset` and reading at most `rawLimit` rows from storage before
    /// the in-memory `postFilter` + dedup run.
    ///
    /// Only valid for buckets WITHOUT a `comparator`: a comparator reorders the
    /// whole result set in memory, which a per-window fetch cannot honor (the
    /// storage `sort` is the only ordering a window can preserve). The Today
    /// `noDate` bucket and the `.all` flat list both sort purely storage-side, so
    /// windowing them is order-identical to the full fetch's corresponding slice.
    /// Callers must NOT window the `today` bucket (it carries `manualThenDueOrder`).
    @MainActor
    public func page(in context: ModelContext, rawOffset: Int, rawLimit: Int) throws -> Page {
        precondition(comparator == nil, "TaskBucket.page is undefined for buckets with a comparator")
        var descriptor = FetchDescriptor<TaskItem>(predicate: predicate, sortBy: sort)
        descriptor.fetchOffset = rawOffset
        descriptor.fetchLimit = rawLimit
        let rawRows = try context.fetch(descriptor)
        let items = rawRows.dedupedByID().filter(postFilter)
        return Page(
            items: items,
            rawCursor: rawOffset + rawRows.count,
            hasMore: rawRows.count == rawLimit
        )
    }
}
