import Foundation
import SwiftData
import Testing

@testable import NexusCore

private actor ScheduleRecorder {
    private(set) var scheduledIDs: [UUID] = []
    func record(_ id: UUID) { scheduledIDs.append(id) }
    func ids() -> [UUID] { scheduledIDs }
}

private struct RecordingScheduler: NotificationScheduling {
    let recorder: ScheduleRecorder
    func schedule(_ task: TaskItem) async throws { await recorder.record(task.id) }
    func cancel(taskID _: UUID) async {}
    func reschedule(_ task: TaskItem) async throws { await recorder.record(task.id) }
    func scheduleSnooze(_ task: TaskItem, until _: Date) async throws { await recorder.record(task.id) }
}

@Suite("I-D1 template inertness — repository guards")
struct TaskItemTemplateGuardTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Note.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    private func makeRepo(
        context: ModelContext,
        notifications: any NotificationScheduling = NoopNotificationScheduler()
    ) -> TaskItemRepository {
        TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            notifications: notifications
        )
    }

    /// Polls the recorder until at least one id arrives (the detached
    /// notification Tasks are FIFO on the main actor, so once the LATER
    /// insert's schedule landed, an earlier skipped one can never appear).
    private func awaitFirstID(_ recorder: ScheduleRecorder) async throws -> [UUID] {
        for _ in 0..<200 {
            let ids = await recorder.ids()
            if !ids.isEmpty { return ids }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        return await recorder.ids()
    }

    @MainActor
    @Test("markDone on a template is a complete no-op and never spawns")
    func markDoneIsNoOpOnTemplate() throws {
        let context = try makeContext()
        let repo = makeRepo(context: context)
        let template = TaskItem(
            title: "tpl",
            dueAt: Date(timeIntervalSince1970: 1_799_000_000),
            recurrenceRule: "FREQ=DAILY",
            isTemplate: true
        )
        try repo.insert(template)

        try repo.markDone(template)

        #expect(template.status == .open)
        #expect(template.lastCompletedAt == nil)
        let rows = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(rows.count == 1)  // no spawned next occurrence
    }

    @MainActor
    @Test("editing the recurrence rule of a done-status template never spawns (I-D1)")
    func ruleEditOnDoneStatusTemplateNeverSpawns() throws {
        let context = try makeContext()
        let repo = makeRepo(context: context)
        let template = TaskItem(
            title: "tpl",
            dueAt: Date(timeIntervalSince1970: 1_799_000_000),
            recurrenceRule: "FREQ=DAILY",
            isTemplate: true
        )
        try repo.insert(template)
        // A template can carry a done statusRaw via sync from a pre-guard
        // build — `completeTask` blocks the forward path, not the stored raw.
        template.statusRaw = TaskStatus.done.rawValue
        template.lastCompletedAt = Date(timeIntervalSince1970: 1_799_500_000)
        try context.save()

        try repo.update(template) { task in
            task.recurrenceRule = "FREQ=WEEKLY"
        }

        let rows = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(rows.count == 1)  // no spawned next occurrence
        #expect(rows.first?.isTemplate == true)
    }

    @MainActor
    @Test("cascadeComplete on a template tree is a no-op")
    func cascadeCompleteIsNoOpOnTemplateTree() throws {
        let context = try makeContext()
        let repo = makeRepo(context: context)
        let parent = TaskItem(title: "tpl parent", isTemplate: true)
        try repo.insert(parent)
        let child = TaskItem(title: "tpl child", parentTaskID: parent.id, isTemplate: true)
        try repo.insert(child)

        try repo.cascadeComplete(parent)

        #expect(parent.status == .open)
        #expect(child.status == .open)
        #expect(parent.lastCompletedAt == nil)
        #expect(child.lastCompletedAt == nil)
    }

    @MainActor
    @Test("setWorkflowState is a no-op on a template")
    func setWorkflowStateIsNoOpOnTemplate() throws {
        let context = try makeContext()
        let repo = makeRepo(context: context)
        let template = TaskItem(title: "tpl", workflowState: .todo, isTemplate: true)
        try repo.insert(template)

        try repo.setWorkflowState(.done, on: template)

        #expect(template.workflowState == .todo)
        #expect(template.status == .open)
        #expect(template.lastCompletedAt == nil)
    }

    @MainActor
    @Test("snooze is a no-op on a template")
    func snoozeIsNoOpOnTemplate() throws {
        let context = try makeContext()
        let repo = makeRepo(context: context)
        let template = TaskItem(title: "tpl", isTemplate: true)
        try repo.insert(template)

        try repo.snooze(template, until: Date(timeIntervalSince1970: 1_900_000_000))

        #expect(template.status == .open)
        #expect(template.snoozedUntil == nil)
    }

    @MainActor
    @Test("insert schedules notifications for live tasks but never for templates")
    func insertSkipsNotificationsForTemplates() async throws {
        let context = try makeContext()
        let recorder = ScheduleRecorder()
        let repo = makeRepo(context: context, notifications: RecordingScheduler(recorder: recorder))
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        let template = TaskItem(title: "tpl", dueAt: due, isTemplate: true)
        let live = TaskItem(title: "live", dueAt: due)
        try repo.insert(template)  // dispatched first if it were scheduled
        try repo.insert(live)

        let ids = try await awaitFirstID(recorder)
        #expect(ids == [live.id])
    }

    @MainActor
    @Test("update reschedules live tasks but never templates")
    func updateSkipsRescheduleForTemplates() async throws {
        let context = try makeContext()
        let recorder = ScheduleRecorder()
        let repo = makeRepo(context: context, notifications: RecordingScheduler(recorder: recorder))
        let template = TaskItem(title: "tpl", isTemplate: true)
        let live = TaskItem(title: "live")
        context.insert(template)
        context.insert(live)
        try context.save()

        try repo.update(template) { $0.title = "tpl renamed" }  // dispatched first if rescheduled
        try repo.update(live) { $0.title = "live renamed" }

        let ids = try await awaitFirstID(recorder)
        #expect(ids == [live.id])
    }
}
