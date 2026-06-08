import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Reconciliation `workflowState ⇄ status` (spec §5). `status` stays the SOLE
/// truth for every existing consumer; `workflowState` is a deterministic overlay.
@Suite("TaskItem workflow reconciliation")
struct TaskItemWorkflowReconciliationTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    private func makeRepo(now: @escaping () -> Date) throws -> (TaskItemRepository, ModelContext) {
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: now)
        return (repo, context)
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Table 5.1 (parameterized: workflowState ⇒ forced status)

    @MainActor
    @Test(
        "table 5.1: setWorkflowState forces the mapped status",
        arguments: [
            (WorkflowState.backlog, TaskStatus.open, false),
            (.todo, .open, false),
            (.inProgress, .open, false),
            (.inReview, .open, false),
            (.done, .done, true),
            (.canceled, .done, false),
            (.duplicate, .done, false),
        ]
    )
    func table51(state: WorkflowState, expectedStatus: TaskStatus, expectsCompletionStamp: Bool) throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "tracker task", workflowState: .backlog)
        try repo.insert(task)

        try repo.setWorkflowState(state, on: task)

        #expect(task.workflowState == state)
        #expect(task.status == expectedStatus)
        // I1: status never diverges from the table for a non-nil workflow.
        #expect(task.statusRaw == expectedStatus.rawValue)
        // I4: only `done` records a completion stamp; canceled/duplicate do not.
        #expect((task.lastCompletedAt != nil) == expectsCompletionStamp)
    }

    // MARK: - I2: snooze is orthogonal

    @MainActor
    @Test("I2: open-group workflow respects an active snooze, returns to open on expiry")
    func snoozeOrthogonal() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x", workflowState: .todo)
        try repo.insert(task)

        // Active snooze: status is snoozed, workflow unchanged.
        try repo.snooze(task, until: now.addingTimeInterval(3600))
        #expect(task.status == .snoozed)
        #expect(task.workflowState == .todo)

        // Re-asserting the open-group workflow during an active snooze must NOT
        // clobber the snooze (I2).
        try repo.setWorkflowState(.inProgress, on: task)
        #expect(task.status == .snoozed)
        #expect(task.workflowState == .inProgress)
        #expect(task.snoozedUntil == now.addingTimeInterval(3600))
    }

    @MainActor
    @Test("I2: unsnooze returns an open-group workflow task to open, workflow intact")
    func unsnoozeReturnsToOpen() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x", workflowState: .todo)
        try repo.insert(task)
        try repo.snooze(task, until: now.addingTimeInterval(-3600))
        try repo.unsnooze(task)
        #expect(task.status == .open)
        #expect(task.workflowState == .todo)
    }

    @MainActor
    @Test("I2: re-asserting open-group after snooze expiry forces open and clears snooze")
    func openGroupAfterExpiredSnooze() throws {
        var current = Self.fixedNow
        let (repo, _) = try makeRepo(now: { current })
        let task = TaskItem(title: "x", workflowState: .todo)
        try repo.insert(task)
        try repo.snooze(task, until: current.addingTimeInterval(3600))
        #expect(task.status == .snoozed)

        // Snooze has elapsed; re-asserting the workflow forces open.
        current = current.addingTimeInterval(7200)
        try repo.setWorkflowState(.todo, on: task)
        #expect(task.status == .open)
        #expect(task.snoozedUntil == nil)
    }

    // MARK: - I3: recurrence-reopen ⇒ todo

    @MainActor
    @Test("I3: completing a recurring project task spawns a todo/open next occurrence")
    func recurrenceReopenToTodo() throws {
        let now = Self.fixedNow
        let (repo, context) = try makeRepo(now: { now })
        let task = TaskItem(
            title: "weekly review",
            dueAt: now,
            recurrenceRule: "FREQ=DAILY",
            workflowState: .inProgress
        )
        try repo.insert(task)

        try repo.markDone(task)

        // Old occurrence: done.
        #expect(task.status == .done)
        #expect(task.workflowState == .done)

        let all = try context.fetch(FetchDescriptor<TaskItem>())
        let spawn = try #require(all.first { $0.id != task.id })
        // New occurrence: todo/open (I3), agent metadata inherited (I8 carry).
        #expect(spawn.workflowState == .todo)
        #expect(spawn.status == .open)
    }

    // MARK: - I4: canceled/duplicate terminal, no completion stamp, no spawn

    @MainActor
    @Test("I4: canceling a recurring task records no completion and spawns nothing")
    func canceledIsTerminal() throws {
        let now = Self.fixedNow
        let (repo, context) = try makeRepo(now: { now })
        let task = TaskItem(
            title: "abandoned recurring",
            dueAt: now,
            recurrenceRule: "FREQ=DAILY",
            workflowState: .inProgress
        )
        try repo.insert(task)

        try repo.setWorkflowState(.canceled, on: task)

        #expect(task.status == .done)
        #expect(task.workflowState == .canceled)
        #expect(task.lastCompletedAt == nil)
        // No next occurrence spawned — terminal, not "work done".
        let all = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(all.count == 1)
    }

    @MainActor
    @Test("I4: duplicate clears an active snooze and records no completion")
    func duplicateClearsSnooze() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "dup", workflowState: .todo)
        try repo.insert(task)
        try repo.snooze(task, until: now.addingTimeInterval(3600))

        try repo.setWorkflowState(.duplicate, on: task)
        #expect(task.status == .done)
        #expect(task.workflowState == .duplicate)
        #expect(task.snoozedUntil == nil)
        #expect(task.lastCompletedAt == nil)
    }

    // MARK: - I1: reopen never leaves a terminal workflow with status=open

    @MainActor
    @Test("reopen on a done project task lands in todo/open")
    func reopenDoneToTodo() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x", workflowState: .inProgress)
        try repo.insert(task)
        try repo.setWorkflowState(.done, on: task)
        #expect(task.status == .done)

        try repo.reopen(task)
        #expect(task.workflowState == .todo)
        #expect(task.status == .open)
        #expect(task.lastCompletedAt == nil)
    }

    @MainActor
    @Test("I1: reopen on a canceled task resets to todo/open (no divergence)")
    func reopenCanceledToTodo() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x", workflowState: .inProgress)
        try repo.insert(task)
        try repo.setWorkflowState(.canceled, on: task)
        #expect(task.status == .done)
        #expect(task.workflowState == .canceled)

        try repo.reopen(task)
        // Terminal -> todo/open; I1 holds (no status=open paired with a terminal state).
        #expect(task.workflowState == .todo)
        #expect(task.status == .open)
    }

    // MARK: - complete via machine == complete via markDone

    @MainActor
    @Test("setWorkflowState(.done) sets lastCompletedAt like markDone")
    func doneViaMachineStampsCompletion() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x", workflowState: .todo)
        try repo.insert(task)

        try repo.setWorkflowState(.done, on: task)
        #expect(task.status == .done)
        #expect(task.workflowState == .done)
        #expect(task.lastCompletedAt == now)
    }

    @MainActor
    @Test("markDone on a project task advances the workflow to done")
    func markDoneAdvancesWorkflow() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x", workflowState: .inProgress)
        try repo.insert(task)

        try repo.markDone(task)
        #expect(task.workflowState == .done)
        #expect(task.status == .done)
        #expect(task.lastCompletedAt == now)
    }
}
