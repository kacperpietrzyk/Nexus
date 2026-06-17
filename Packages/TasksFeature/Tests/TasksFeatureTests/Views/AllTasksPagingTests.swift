import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

/// Windowed (paginated) `.all` flat-list fetch for the Tasks list perf pass
/// (`perf/today-data-scaling`). Asserts the windowed page core is order-identical
/// to slicing the full `tasks(status: nil)` fetch, with no gaps/overlaps, and that
/// the union of pages equals the full result (same set, same order).
@MainActor
@Suite("All tasks paging")
struct AllTasksPagingTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Seeds `count` open, no-date root tasks with distinct `createdAt` so the
    /// `(dueAt fwd, createdAt rev)` sort is total/stable across `fetchOffset`
    /// queries (all share a nil `dueAt`, so createdAt is the sole discriminator).
    private func seed(_ count: Int, in context: ModelContext) {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            let task = TaskItem(title: "task-\(index)")
            task.createdAt = base.addingTimeInterval(Double(index))
            context.insert(task)
        }
    }

    @Test("page 1 returns the first 50 in the same order as the full fetch's first 50")
    func page1MatchesFullPrefix() throws {
        let context = try makeContext()
        seed(200, in: context)
        try context.save()

        let full = try TaskListView.tasks(status: nil, modelContext: context)
        let page1 = try TaskListView.allTasksPage(rawOffset: 0, rawLimit: 50, modelContext: context)

        #expect(page1.items.map(\.id) == Array(full.prefix(50)).map(\.id))
        #expect(page1.hasMore)
        #expect(page1.rawCursor == 50)
    }

    @Test("page 2 returns items 51-150 with no overlap or gap vs page 1")
    func page2MatchesFullSlice() throws {
        let context = try makeContext()
        seed(200, in: context)
        try context.save()

        let full = try TaskListView.tasks(status: nil, modelContext: context)
        let page1 = try TaskListView.allTasksPage(rawOffset: 0, rawLimit: 50, modelContext: context)
        let page2 = try TaskListView.allTasksPage(
            rawOffset: page1.rawCursor,
            rawLimit: 100,
            modelContext: context
        )

        #expect(page2.items.map(\.id) == Array(full[50..<150]).map(\.id))
        let overlap = Set(page1.items.map(\.id)).intersection(page2.items.map(\.id))
        #expect(overlap.isEmpty)
    }

    @Test("union of pages equals the full non-windowed fetch (same set, same order)")
    func unionOfPagesEqualsFull() throws {
        let context = try makeContext()
        seed(283, in: context)
        try context.save()

        let full = try TaskListView.tasks(status: nil, modelContext: context)

        var loaded: [TaskItem] = []
        var cursor = 0
        var limit = 50
        while true {
            let page = try TaskListView.allTasksPage(
                rawOffset: cursor,
                rawLimit: limit,
                modelContext: context
            )
            loaded.append(contentsOf: page.items)
            cursor = page.rawCursor
            limit = 100
            if !page.hasMore { break }
        }

        #expect(loaded.map(\.id) == full.map(\.id))
        #expect(loaded.count == 283)
    }

    @Test("a windowed page excludes subtasks and done tasks")
    func pageExcludesSubtasksAndDone() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let root = TaskItem(title: "root")
        root.createdAt = base
        context.insert(root)
        let child = TaskItem(title: "child", parentTaskID: root.id)
        child.createdAt = base.addingTimeInterval(1)
        context.insert(child)
        let done = TaskItem(title: "done")
        done.statusRaw = TaskStatus.done.rawValue
        done.createdAt = base.addingTimeInterval(2)
        context.insert(done)
        try context.save()

        let page = try TaskListView.allTasksPage(rawOffset: 0, rawLimit: 50, modelContext: context)

        #expect(page.items.map(\.id) == [root.id])
    }
}
