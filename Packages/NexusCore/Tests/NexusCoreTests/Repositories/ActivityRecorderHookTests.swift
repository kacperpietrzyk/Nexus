import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItemRepository activity hooks — lifecycle")
@MainActor
struct ActivityRecorderHookTests {

    // swiftlint:disable:next large_tuple
    private func makeFixture() throws -> (
        repo: TaskItemRepository, context: ModelContext, reader: ActivityEntryRepository
    ) {
        let schema = Schema([
            TaskItem.self, ActivityEntry.self, Project.self, Section.self, Comment.self, Note.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let repo = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            notifications: NoopNotificationScheduler(),
            activity: ActivityRecorder(context: context, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        )
        return (repo, context, ActivityEntryRepository(context: context))
    }

    /// Seed a task WITHOUT the repository so it carries no `created` event —
    /// keeps per-method assertions exact.
    private func seed(_ task: TaskItem, in context: ModelContext) throws {
        context.insert(task)
        try context.save()
    }

    // MARK: insert → created

    @Test("insert records created, and the entry rides the host save (survives rollback)")
    func insertRecordsCreatedAtomically() throws {
        let (repo, context, reader) = try makeFixture()
        let task = TaskItem(title: "audit me")

        try repo.insert(task)
        context.rollback()  // anything UN-saved would vanish here

        let events = try reader.entries(for: task.id, kind: .task, limit: 10)
        #expect(events.map(\.eventKindRaw) == [ActivityEventKind.created.rawValue])
    }

    @Test("insert of a template records nothing (I-D1: templates are inert)")
    func insertTemplateRecordsNothing() throws {
        let (repo, _, reader) = try makeFixture()
        let template = TaskItem(title: "template")
        template.isTemplate = true

        try repo.insert(template)

        #expect(try reader.entries(for: template.id, kind: .task, limit: 10).isEmpty)
    }

    // MARK: completeTask choke point → completed

    @Test("markDone records completed once; a second markDone records nothing (early-return guard)")
    func markDoneRecordsCompletedOnce() throws {
        let (repo, context, reader) = try makeFixture()
        let task = TaskItem(title: "done me")
        try seed(task, in: context)

        try repo.markDone(task)
        try repo.markDone(task)

        let events = try reader.entries(for: task.id, kind: .task, limit: 10)
        #expect(events.map(\.eventKindRaw) == [ActivityEventKind.completed.rawValue])
    }

    @Test("cascadeComplete records completed for the parent AND each subtask")
    func cascadeCompleteRecordsPerSubtask() throws {
        let (repo, context, reader) = try makeFixture()
        let parent = TaskItem(title: "parent")
        try seed(parent, in: context)
        let child = TaskItem(title: "child", parentTaskID: parent.id)
        try seed(child, in: context)

        try repo.cascadeComplete(parent)

        #expect(
            try reader.entries(for: parent.id, kind: .task, limit: 10).map(\.eventKindRaw)
                == [ActivityEventKind.completed.rawValue]
        )
        #expect(
            try reader.entries(for: child.id, kind: .task, limit: 10).map(\.eventKindRaw)
                == [ActivityEventKind.completed.rawValue]
        )
    }

    @Test("completing a recurring task records completed for it and created for the spawned occurrence")
    func recurringCompletionRecordsSpawnCreated() throws {
        let (repo, context, reader) = try makeFixture()
        let task = TaskItem(
            title: "recurring",
            dueAt: Date(timeIntervalSince1970: 1_699_999_000),
            recurrenceRule: "FREQ=DAILY"
        )
        try seed(task, in: context)

        try repo.markDone(task)

        #expect(
            try reader.entries(for: task.id, kind: .task, limit: 10).map(\.eventKindRaw)
                == [ActivityEventKind.completed.rawValue]
        )
        let parentID = task.id
        let openRaw = TaskStatus.open.rawValue
        let spawns = try context.fetch(
            FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.recurrenceParentId == parentID && $0.statusRaw == openRaw }
            )
        )
        let spawn = try #require(spawns.first)
        #expect(
            try reader.entries(for: spawn.id, kind: .task, limit: 10).map(\.eventKindRaw)
                == [ActivityEventKind.created.rawValue]
        )
    }

    // MARK: reopen → reopened

    @Test("reopen records reopened after the early-return guard")
    func reopenRecordsReopened() throws {
        let (repo, context, reader) = try makeFixture()
        let task = TaskItem(title: "cycle me")
        try seed(task, in: context)
        try repo.markDone(task)

        try repo.reopen(task)

        let kinds = Set(try reader.entries(for: task.id, kind: .task, limit: 10).map(\.eventKindRaw))
        #expect(kinds == [ActivityEventKind.completed.rawValue, ActivityEventKind.reopened.rawValue])
    }

    @Test("reopen of a never-completed open task records nothing (early return)")
    func reopenOpenTaskRecordsNothing() throws {
        let (repo, context, reader) = try makeFixture()
        let task = TaskItem(title: "already open")
        try seed(task, in: context)

        try repo.reopen(task)

        #expect(try reader.entries(for: task.id, kind: .task, limit: 10).isEmpty)
    }

    // MARK: out-of-scope pins (spec §4.1: snooze/unsnooze/reorder are NOT logged)

    @Test("snooze and reorder record nothing (explicitly out of scope v1)")
    func snoozeAndReorderRecordNothing() throws {
        let (repo, context, reader) = try makeFixture()
        let task = TaskItem(title: "quiet ops")
        try seed(task, in: context)

        try repo.snooze(task, until: Date(timeIntervalSince1970: 1_700_000_600))
        try repo.reorder([task])

        #expect(try reader.entries(for: task.id, kind: .task, limit: 10).isEmpty)
    }
}
