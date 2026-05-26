import Foundation
import InboxShell
import NexusCore
import SwiftData
import TasksFeature
import Testing

@MainActor
@Suite("Tasks inbox sources")
struct InboxFlowTests {

    @Test("no-date source includes open no-date tasks and archive soft-deletes")
    func noDateSourceArchive() async throws {
        let harness = try Harness()
        let task = TaskItem(title: "Plan week", body: "notes", tags: ["planning"])
        try harness.repository.insert(task)
        let source = TasksNoDateSource(repository: harness.repository)

        let items = try await source.items()
        #expect(items.map(\.title) == ["Plan week"])

        try await source.archive(items[0])
        let afterArchive = try await source.items()
        #expect(afterArchive.isEmpty)
    }

    @Test("snoozed source includes future snoozed tasks and snooze updates date")
    func snoozedSource() async throws {
        let harness = try Harness()
        let task = TaskItem(title: "Call dentist")
        try harness.repository.insert(task)
        try harness.repository.snooze(task, until: harness.now.addingTimeInterval(3600))
        let source = TasksSnoozedSource(repository: harness.repository, now: { harness.now })

        let items = try await source.items()
        #expect(items.map(\.title) == ["Call dentist"])

        try await source.snooze(items[0], until: harness.now.addingTimeInterval(7200))
        #expect(task.snoozedUntil == harness.now.addingTimeInterval(7200))
    }

    @Test("snoozed source archive clears snooze and reopens task")
    func snoozedSourceArchive() async throws {
        let harness = try Harness()
        let task = TaskItem(title: "Call plumber")
        try harness.repository.insert(task)
        try harness.repository.snooze(task, until: harness.now.addingTimeInterval(3600))
        let source = TasksSnoozedSource(repository: harness.repository, now: { harness.now })

        let items = try await source.items()
        #expect(items.map(\.title) == ["Call plumber"])

        try await source.archive(items[0])

        let afterArchive = try await source.items()
        #expect(afterArchive.isEmpty)
        #expect(task.snoozedUntil == nil)
        #expect(task.status == .open)
    }
}

@MainActor
private struct Harness {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let container: ModelContainer
    let repository: TaskItemRepository

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: TaskItem.self, configurations: config)
        self.repository = TaskItemRepository(
            context: container.mainContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }
}
