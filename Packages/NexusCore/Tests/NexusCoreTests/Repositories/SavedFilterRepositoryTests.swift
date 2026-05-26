import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("SavedFilterRepository")
struct SavedFilterRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([SavedFilter.self, TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("create appends filters after existing order indexes and all returns sorted")
    func createAppendsAndAllSorts() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = SavedFilterRepository(context: context, now: { stamp })

        let first = try repo.create(name: "Inbox", definition: .unsorted)
        let second = try repo.create(name: "Work", definition: .byTag("work"), icon: "briefcase")
        let third = try repo.create(name: "Soon", definition: .dueWithin(days: 2))

        #expect(first.orderIndex == 1.0)
        #expect(second.orderIndex == 2.0)
        #expect(third.orderIndex == 3.0)
        #expect(second.icon == "briefcase")
        #expect(first.createdAt == stamp)
        #expect(first.updatedAt == stamp)
        #expect(try repo.all().map(\.name) == ["Inbox", "Work", "Soon"])
    }

    @MainActor
    @Test("update changes optional fields through throwing definition encoder")
    func updateChangesOptionalFields() throws {
        var current = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = SavedFilterRepository(context: context, now: { current })
        let filter = try repo.create(name: "Old", definition: .byTag("old"))

        current = current.addingTimeInterval(60)
        try repo.update(filter, name: "New", definition: .byTag("new"))

        #expect(filter.name == "New")
        #expect(try filter.decodedDefinition() == .byTag("new"))
        #expect(filter.updatedAt == current)
    }

    @MainActor
    @Test("reorder assigns midpoint between neighbors")
    func reorderMidpoint() throws {
        let context = try makeContext()
        let repo = SavedFilterRepository(context: context)
        let first = try repo.create(name: "First", definition: .unsorted)
        let second = try repo.create(name: "Second", definition: .byTag("second"))
        let third = try repo.create(name: "Third", definition: .byTag("third"))

        try repo.reorder(third, between: first, and: second)

        #expect(third.orderIndex == 1.5)
        #expect(try repo.all().map(\.name) == ["First", "Third", "Second"])
    }

    @MainActor
    @Test("find returns filter by id and delete soft-deletes the row")
    func findAndDelete() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = SavedFilterRepository(context: context, now: { stamp })
        let filter = try repo.create(name: "Find me", definition: .byTag("work"))

        #expect(try repo.find(filter.id)?.id == filter.id)

        try repo.delete(filter)

        // Soft-delete: the row stays in the store so CloudKit can propagate the
        // tombstone; only the public find/all helpers hide it.
        #expect(filter.deletedAt == stamp)
        #expect(filter.updatedAt == stamp)
        let raw = try context.fetch(FetchDescriptor<SavedFilter>())
        #expect(raw.map(\.id) == [filter.id])
        #expect(try repo.find(filter.id) == nil)
        #expect(try repo.all().isEmpty)
    }

    @MainActor
    @Test("find excludes soft-deleted filters")
    func findExcludesSoftDeletedFilters() throws {
        let context = try makeContext()
        let repo = SavedFilterRepository(context: context)
        let filter = try repo.create(name: "Archived", definition: .byTag("work"))
        filter.deletedAt = .now
        try context.save()

        #expect(try repo.find(filter.id) == nil)
    }

    @MainActor
    @Test("apply hydrates active tasks and runs decoded definition matcher")
    func applyMatchesActiveTasks() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = SavedFilterRepository(
            context: context,
            now: { now },
            calendar: Calendar(identifier: .gregorian)
        )
        let projectID = UUID()
        let matching = TaskItem(
            title: "Match",
            dueAt: now.addingTimeInterval(86_400),
            priority: .high,
            tags: ["work"],
            projectID: projectID,
            orderIndex: 1.0
        )
        let wrongTag = TaskItem(
            title: "Wrong tag",
            dueAt: now.addingTimeInterval(86_400),
            priority: .high,
            tags: ["home"],
            projectID: projectID,
            orderIndex: 2.0
        )
        let done = TaskItem(
            title: "Done",
            dueAt: now.addingTimeInterval(86_400),
            priority: .high,
            status: .done,
            tags: ["work"],
            projectID: projectID,
            orderIndex: 3.0
        )
        let snoozed = TaskItem(
            title: "Snoozed",
            dueAt: now.addingTimeInterval(86_400),
            priority: .high,
            status: .snoozed,
            tags: ["work"],
            projectID: projectID,
            orderIndex: 4.0
        )
        let deleted = TaskItem(
            title: "Deleted",
            dueAt: now.addingTimeInterval(86_400),
            priority: .high,
            tags: ["work"],
            projectID: projectID,
            orderIndex: 5.0
        )
        deleted.deletedAt = now
        [matching, wrongTag, done, snoozed, deleted].forEach(context.insert)
        let filter = try repo.create(
            name: "Work soon",
            definition: .and([.byTag("work"), .byProject(projectID), .dueWithin(days: 2), .priorityAtLeast(.medium)])
        )
        try context.save()

        let result = try repo.apply(filter, now: now)

        #expect(result.map(\.title) == ["Match"])
    }

    @MainActor
    @Test("apply sorts non-nil order indexes before nil order indexes")
    func applySortsNilOrderIndexesLast() throws {
        let context = try makeContext()
        let repo = SavedFilterRepository(context: context)
        let first = TaskItem(title: "First", tags: ["work"], orderIndex: 1.0)
        let second = TaskItem(title: "Second", tags: ["work"], orderIndex: 2.0)
        let nilOrder = TaskItem(title: "Nil order", tags: ["work"])
        [nilOrder, second, first].forEach(context.insert)
        let filter = try repo.create(name: "Work", definition: .byTag("work"))
        try context.save()

        let result = try repo.apply(filter)

        #expect(result.map(\.title) == ["First", "Second", "Nil order"])
    }

    @MainActor
    @Test("apply propagates corrupt filter decode failures")
    func applyThrowsForCorruptFilter() throws {
        let context = try makeContext()
        let repo = SavedFilterRepository(context: context)
        let filter = try repo.create(name: "Broken", definition: .byTag("work"))
        filter.definitionJSON = Data("not-json".utf8)
        try context.save()

        var didThrow = false
        do {
            _ = try repo.apply(filter)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}
