import Foundation
import SwiftData
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("Saved filter task list data source")
struct SavedFilterTaskListTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([SavedFilter.self, TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("applies saved filter through repository and returns only root matches")
    func appliesSavedFilterAndReturnsOnlyRootMatches() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repository = SavedFilterRepository(context: context, now: { now })

        let root = TaskItem(title: "Root match", tags: ["work"], orderIndex: 1.0)
        let child = TaskItem(title: "Child match", tags: ["work"], parentTaskID: root.id, orderIndex: 0.5)
        let wrongTag = TaskItem(title: "Wrong tag", tags: ["home"], orderIndex: 2.0)
        let done = TaskItem(title: "Done match", status: .done, tags: ["work"], orderIndex: 3.0)
        [root, child, wrongTag, done].forEach(context.insert)

        let filter = try repository.create(name: "Work", definition: .byTag("work"))
        try context.save()

        let result = try TaskListView.savedFilterTasks(
            filterID: filter.id,
            now: now,
            modelContext: context
        )

        #expect(result.map(\.title) == ["Root match"])
    }

    @MainActor
    @Test("missing saved filters surface as task list errors")
    func missingSavedFilterThrows() throws {
        let context = try makeContext()

        do {
            _ = try TaskListView.savedFilterTasks(
                filterID: UUID(),
                now: .now,
                modelContext: context
            )
            Issue.record("Expected missing saved filter to throw.")
        } catch {
            #expect(String(describing: error) == "This Smart List no longer exists.")
        }
    }

    @MainActor
    @Test("corrupt saved filters surface as task list errors")
    func corruptSavedFilterThrows() throws {
        let context = try makeContext()
        let repository = SavedFilterRepository(context: context)
        let filter = try repository.create(name: "Broken", definition: .byTag("work"))
        filter.definitionJSON = Data("not-json".utf8)
        try context.save()

        do {
            _ = try TaskListView.savedFilterTasks(
                filterID: filter.id,
                now: .now,
                modelContext: context
            )
            Issue.record("Expected corrupt saved filter to throw.")
        } catch {
            #expect(String(describing: error) == "This Smart List cannot be decoded. Delete it and save the filter again.")
        }
    }
}
