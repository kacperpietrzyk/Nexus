import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Windowed-loading core for the Inbox perf pass (`perf/today-data-scaling`).
///
/// The Inbox's GLOBAL sort is `createdAt` desc then title; `noDate()`'s Today
/// ordering (`priorityRaw` desc, `createdAt` desc) does NOT compose with it
/// (a later page could surface a newer, lower-priority item that belongs ABOVE
/// an already-shown row). `noDateInboxWindow()` re-sorts to `createdAt` desc +
/// `id` tiebreak so paged windows always extend the loaded prefix at the tail.
///
/// Also covers the cheap COUNT path (`fetchCount`, no materialization) that keeps
/// the Inbox badge / "All" tab accurate while only a 50-item window is loaded.
@Suite("Inbox no-date window")
struct InboxNoDateWindowTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Seeds `count` no-date open tasks with strictly-distinct `createdAt` so the
    /// `(createdAt desc, id asc)` sort is total and stable across separate
    /// `fetchOffset` queries (no SQLite tie-break flake).
    @MainActor
    private func seedNoDate(_ count: Int, in context: ModelContext) {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            let task = TaskItem(title: "task-\(index)")
            task.createdAt = base.addingTimeInterval(Double(index))
            context.insert(task)
        }
    }

    // MARK: - Windowed order

    @MainActor
    @Test("inbox window is createdAt-desc, NOT priority-first (composes with global sort)")
    func windowIsCreatedAtDescNotPriorityFirst() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // The OLDEST task carries the HIGHEST priority. A priority-first sort (the
        // Today `noDate()` ordering) would float it to the TOP of page 1; the Inbox
        // global sort is createdAt-desc, so it must instead sit at the BOTTOM. This
        // is the discriminator that fails if the window reuses `noDate()`'s order.
        for index in 0..<10 {
            let task = TaskItem(title: "task-\(index)")
            task.createdAt = base.addingTimeInterval(Double(index))
            task.priorityRaw = index == 0 ? 3 : 0
            context.insert(task)
        }
        try context.save()
        let bucket = TodayQuery().noDateInboxWindow()

        let items = try bucket.apply(in: context)

        // Newest-first regardless of priority: task-9 leads, the high-priority
        // task-0 trails.
        #expect(items.first?.title == "task-9")
        #expect(items.last?.title == "task-0")
    }

    @MainActor
    @Test("inbox window page 1 == first 50 of the full createdAt-desc list, same order")
    func page1MatchesFullPrefix() throws {
        let context = try makeContext()
        seedNoDate(200, in: context)
        try context.save()
        let bucket = TodayQuery().noDateInboxWindow()

        let full = try bucket.apply(in: context)
        let page1 = try bucket.page(in: context, rawOffset: 0, rawLimit: 50)

        #expect(page1.items.map(\.id) == Array(full.prefix(50)).map(\.id))
        // Sorted newest-first: the very first item is the highest createdAt.
        #expect(page1.items.first?.title == "task-199")
        #expect(page1.hasMore)
        #expect(page1.rawCursor == 50)
    }

    @MainActor
    @Test("inbox window page 2 == items 51-150, no overlap or gap vs page 1")
    func page2MatchesFullSlice() throws {
        let context = try makeContext()
        seedNoDate(200, in: context)
        try context.save()
        let bucket = TodayQuery().noDateInboxWindow()

        let full = try bucket.apply(in: context)
        let page1 = try bucket.page(in: context, rawOffset: 0, rawLimit: 50)
        let page2 = try bucket.page(in: context, rawOffset: page1.rawCursor, rawLimit: 100)

        #expect(page2.items.map(\.id) == Array(full[50..<150]).map(\.id))
        let overlap = Set(page1.items.map(\.id)).intersection(page2.items.map(\.id))
        #expect(overlap.isEmpty)
    }

    @MainActor
    @Test("union of inbox-window pages equals the full createdAt-desc fetch")
    func unionOfPagesEqualsFull() throws {
        let context = try makeContext()
        seedNoDate(283, in: context)
        try context.save()
        let bucket = TodayQuery().noDateInboxWindow()

        let full = try bucket.apply(in: context)

        // Drive the exact paging loop the view uses: first page 50, then +100.
        var loaded: [TaskItem] = []
        var cursor = 0
        var limit = 50
        while true {
            let page = try bucket.page(in: context, rawOffset: cursor, rawLimit: limit)
            loaded.append(contentsOf: page.items)
            cursor = page.rawCursor
            limit = 100
            if !page.hasMore { break }
        }

        #expect(loaded.map(\.id) == full.map(\.id))
        #expect(loaded.count == 283)
    }

    @MainActor
    @Test("duplicate createdAt: id tiebreak keeps paging gap-free and total-ordered")
    func duplicateCreatedAtPagesGapFree() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Many tasks share a createdAt (true on the migrated store: created_at was
        // back-dated in bulk). Without the `id` tiebreak, offset/limit windows over
        // an equal-createdAt cluster could re-order across page boundaries → gaps.
        for index in 0..<120 {
            let task = TaskItem(title: "task-\(index)")
            // Three distinct timestamps, 40 tasks each → big equal-createdAt clusters.
            task.createdAt = base.addingTimeInterval(Double(index / 40))
            context.insert(task)
        }
        try context.save()
        let bucket = TodayQuery().noDateInboxWindow()

        let full = try bucket.apply(in: context)
        var loaded: [TaskItem] = []
        var cursor = 0
        var limit = 50
        while true {
            let page = try bucket.page(in: context, rawOffset: cursor, rawLimit: limit)
            loaded.append(contentsOf: page.items)
            cursor = page.rawCursor
            limit = 100
            if !page.hasMore { break }
        }

        #expect(loaded.map(\.id) == full.map(\.id))
        #expect(Set(loaded.map(\.id)).count == 120)
    }

    @MainActor
    @Test("inbox window SET matches noDate(): subtasks included, order differs only")
    func sameSetAsNoDate() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let root = TaskItem(title: "root")
        root.createdAt = base.addingTimeInterval(1)
        let child = TaskItem(title: "child", parentTaskID: root.id)
        child.createdAt = base.addingTimeInterval(2)
        context.insert(root)
        context.insert(child)
        try context.save()
        let query = TodayQuery()

        let noDateSet = Set(try query.noDate().apply(in: context).map(\.id))
        let windowSet = Set(try query.noDateInboxWindow().apply(in: context).map(\.id))

        // Identical SET (the windowed source must surface the same items as today,
        // subtasks INCLUDED — only the order is re-sorted createdAt-desc).
        #expect(windowSet == noDateSet)
        #expect(windowSet.contains(child.id))
    }

    // MARK: - Count path (no materialization)

    @MainActor
    @Test("count returns the TRUE total without materializing the window")
    func countReturnsTrueTotal() throws {
        let context = try makeContext()
        seedNoDate(120, in: context)
        try context.save()
        let bucket = TodayQuery().noDateInboxWindow()

        // Only 50 materialized via the window...
        let page1 = try bucket.page(in: context, rawOffset: 0, rawLimit: 50)
        #expect(page1.items.count == 50)

        // ...yet the count path reports the full 120 (it does NOT depend on the
        // window — proves the badge stays accurate while windowed).
        let count = try bucket.count(in: context)
        #expect(count == 120)
    }

    @MainActor
    @Test("count includes archived-project tasks (documented fetchCount divergence)")
    func countIncludesArchivedProjects() throws {
        let context = try makeContext()
        let archivedProjectID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<10 {
            let task = TaskItem(
                title: "task-\(index)",
                projectID: index < 4 ? archivedProjectID : nil
            )
            task.createdAt = base.addingTimeInterval(Double(index))
            context.insert(task)
        }
        try context.save()
        let bucket = TodayQuery().noDateInboxWindow(excludingProjectIDs: [archivedProjectID])

        // The post-filter drops the 4 archived-project tasks from the MATERIALIZED
        // list (6 survive)...
        let materialized = try bucket.apply(in: context)
        #expect(materialized.count == 6)

        // ...but fetchCount evaluates only the storage predicate, so the COUNT
        // includes all 10. This is the documented over-count direction: the badge
        // can over-report by the number of archived-project no-date tasks.
        let count = try bucket.count(in: context)
        #expect(count == 10)
    }
}
