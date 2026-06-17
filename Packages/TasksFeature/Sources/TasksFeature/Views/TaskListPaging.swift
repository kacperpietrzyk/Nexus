import Foundation
import NexusCore
import SwiftData
import SwiftUI

/// Windowed-loading state for the high-volume `.all` and `.today` filters of
/// `TaskListView`. Only the `.all` flat list and the Today `noDate` bucket are
/// windowed (both are purely DB-sorted, so a window is order-identical to a slice
/// of the full fetch); the tiny `overdue`/`today` buckets load fully.
///
/// Paging is by RAW DB cursor, not by surviving-row count: a window can lose rows
/// to the in-memory dedup/post-filter, so the next page must resume at the raw
/// offset the storage scan reached (`rawCursor`) to stay gap-free and
/// overlap-free. See `TaskBucket.page`.
struct TaskListPageState: Equatable {
    /// Rows loaded on the very first page; the rest stream in `pageSize` at a time.
    static let firstPageSize = 50
    /// Rows appended per scroll-triggered load.
    static let pageSize = 100
    /// Prefetch margin: trigger the next load when the row this many from the end
    /// appears, so the fetch completes before the user reaches the bottom.
    static let prefetchMargin = 10

    /// Raw DB cursor for the `.all` flat list (and unused for `.today`).
    var flatCursor = 0
    var flatHasMore = false

    /// Raw DB cursor for the Today `noDate` bucket.
    var noDateCursor = 0
    var noDateHasMore = false

    /// Re-entrancy guard so a burst of `onAppear`s near the end can't fire several
    /// overlapping fetches.
    var isLoadingMore = false

    /// Whether either windowed stream still has pages to fetch.
    var hasMore: Bool { flatHasMore || noDateHasMore }

    mutating func reset() {
        self = TaskListPageState()
    }
}

extension TaskListPageState {
    /// The effective stagger index for a row at absolute list position `index`:
    /// capped so appended pages don't inherit multi-second
    /// `0.18 + index * 0.09` enter delays (a row at index 50 would wait ~4.6 s).
    /// The first page keeps its real stagger up to the cap; everything past the
    /// cap enters together. Pure presentation — no data change.
    static let staggerCap = 12

    static func cappedAppearIndex(_ index: Int) -> Int {
        min(index, staggerCap)
    }
}
