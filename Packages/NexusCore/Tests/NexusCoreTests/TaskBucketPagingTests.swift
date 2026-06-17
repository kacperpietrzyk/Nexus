import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Windowed (paginated) bucket fetch core for the Tasks list perf pass
/// (`perf/today-data-scaling`). Asserts that paging `noDate` by raw DB cursor is
/// order-identical to slicing the full non-windowed fetch, with no gaps/overlaps,
/// and that the archived-project + subtask exclusions still hold per page.
@Suite("TaskBucket paging")
struct TaskBucketPagingTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Seeds `count` no-date open root tasks with strictly-distinct `createdAt`
    /// values so the `(priorityRaw desc, createdAt desc)` sort is total and stable
    /// across separate `fetchOffset` queries (no SQLite tie-break flake).
    @MainActor
    private func seedNoDate(_ count: Int, in context: ModelContext) {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            let task = TaskItem(title: "task-\(index)")
            // Distinct, monotonically increasing createdAt; same priority so the
            // sort tie-breaks purely on createdAt (descending = newest first).
            task.createdAt = base.addingTimeInterval(Double(index))
            context.insert(task)
        }
    }

    @MainActor
    @Test("page 1 returns the first 50 in the same order as the full fetch's first 50")
    func page1MatchesFullPrefix() throws {
        let context = try makeContext()
        seedNoDate(200, in: context)
        try context.save()
        let bucket = TodayQuery().noDateRoots()

        let full = try bucket.apply(in: context)
        let page1 = try bucket.page(in: context, rawOffset: 0, rawLimit: 50)

        #expect(page1.items.map(\.id) == Array(full.prefix(50)).map(\.id))
        #expect(page1.hasMore)
        #expect(page1.rawCursor == 50)
    }

    @MainActor
    @Test("page 2 returns items 51-150 with no overlap or gap vs page 1")
    func page2MatchesFullSlice() throws {
        let context = try makeContext()
        seedNoDate(200, in: context)
        try context.save()
        let bucket = TodayQuery().noDateRoots()

        let full = try bucket.apply(in: context)
        let page1 = try bucket.page(in: context, rawOffset: 0, rawLimit: 50)
        let page2 = try bucket.page(in: context, rawOffset: page1.rawCursor, rawLimit: 100)

        #expect(page2.items.map(\.id) == Array(full[50..<150]).map(\.id))
        // No overlap between consecutive pages.
        let overlap = Set(page1.items.map(\.id)).intersection(page2.items.map(\.id))
        #expect(overlap.isEmpty)
    }

    @MainActor
    @Test("union of pages equals the full non-windowed fetch (same set, same order)")
    func unionOfPagesEqualsFull() throws {
        let context = try makeContext()
        seedNoDate(283, in: context)
        try context.save()
        let bucket = TodayQuery().noDateRoots()

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
    @Test("a windowed page still excludes archived-project tasks")
    func pageExcludesArchivedProjects() throws {
        let context = try makeContext()
        let archivedProjectID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Interleave archived rows among active ones so the exclusion has to bite
        // inside a single window, not just at the tail.
        for index in 0..<60 {
            let task = TaskItem(
                title: "task-\(index)",
                projectID: index.isMultiple(of: 3) ? archivedProjectID : nil
            )
            task.createdAt = base.addingTimeInterval(Double(index))
            context.insert(task)
        }
        try context.save()
        let bucket = TodayQuery().noDateRoots(excludingProjectIDs: [archivedProjectID])

        let page = try bucket.page(in: context, rawOffset: 0, rawLimit: 30)

        #expect(page.items.allSatisfy { $0.projectID != archivedProjectID })
        // Raw cursor advanced by raw rows read (30), even though some were filtered.
        #expect(page.rawCursor == 30)
    }

    @MainActor
    @Test("a windowed page excludes subtasks (parentTaskID hoisted into predicate)")
    func pageExcludesSubtasks() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let parent = TaskItem(title: "parent")
        parent.createdAt = base
        context.insert(parent)
        for index in 0..<20 {
            let child = TaskItem(title: "child-\(index)", parentTaskID: parent.id)
            child.createdAt = base.addingTimeInterval(Double(index + 1))
            context.insert(child)
        }
        try context.save()
        let bucket = TodayQuery().noDateRoots()

        let page = try bucket.page(in: context, rawOffset: 0, rawLimit: 50)

        #expect(page.items.map(\.id) == [parent.id])
        #expect(!page.hasMore)
    }

    @MainActor
    @Test("paging WITH an active post-filter: union of pages equals the full fetch (no gaps/overlaps)")
    func unionOfPagesEqualsFullWithPostFilter() throws {
        let context = try makeContext()
        let archivedProjectID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Interleave archived (post-filtered-out) rows densely among survivors so
        // a per-page filter is active on EVERY page. If the cursor advanced by
        // surviving-row count instead of raw rows read, consecutive pages would
        // re-read or skip rows → this union would gap/overlap vs the full fetch.
        for index in 0..<250 {
            let task = TaskItem(
                title: "task-\(index)",
                projectID: index.isMultiple(of: 2) ? archivedProjectID : nil
            )
            task.createdAt = base.addingTimeInterval(Double(index))
            context.insert(task)
        }
        try context.save()
        let bucket = TodayQuery().noDateRoots(excludingProjectIDs: [archivedProjectID])

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
        #expect(loaded.allSatisfy { $0.projectID != archivedProjectID })
        #expect(loaded.count == full.count)
    }

    @MainActor
    @Test("noDateRoots full fetch equals rootTasks(noDate()) — visible set + order identical")
    func noDateRootsEqualsRootsOfNoDate() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // A mix the legacy `noDate()` returns raw (and callers root-reduce): roots,
        // subtasks, a template, a deleted row.
        let rootA = TaskItem(title: "root-a")
        rootA.createdAt = base.addingTimeInterval(1)
        let rootB = TaskItem(title: "root-b")
        rootB.createdAt = base.addingTimeInterval(2)
        let child = TaskItem(title: "child", parentTaskID: rootA.id)
        child.createdAt = base.addingTimeInterval(3)
        let template = TaskItem(title: "template")
        template.isTemplate = true
        template.createdAt = base.addingTimeInterval(4)
        let deleted = TaskItem(title: "deleted")
        deleted.deletedAt = base
        deleted.createdAt = base.addingTimeInterval(5)
        for task in [rootA, rootB, child, template, deleted] { context.insert(task) }
        try context.save()

        let query = TodayQuery()
        // What the non-windowed Tasks list shows today: roots of the raw bucket.
        let legacyVisible = try query.noDate().apply(in: context)
            .filter { $0.parentTaskID == nil }
        let rootsBucket = try query.noDateRoots().apply(in: context)

        #expect(rootsBucket.map(\.id) == legacyVisible.map(\.id))
        #expect(rootsBucket.map(\.id) == [rootB.id, rootA.id])
    }
}
