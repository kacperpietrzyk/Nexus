import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Invariant I7 (the biggest regression risk): a GTD task (`workflowState == nil`)
/// keeps 100% of its pre-Projects behavior — no query/widget/notification/recurrence
/// result changes. I8: `assignedAgent` is pure metadata with zero side effects.
@Suite("TaskItem GTD regression (I7 / I8)")
struct TaskItemGTDRegressionTests {
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

    // MARK: - I7: GTD task lifecycle unchanged

    @MainActor
    @Test("I7: a new GTD task has nil workflowState and nil agent")
    func gtdDefaultsNil() throws {
        let (repo, _) = try makeRepo(now: { Self.fixedNow })
        let task = TaskItem(title: "buy milk")
        try repo.insert(task)
        #expect(task.workflowState == nil)
        #expect(task.workflowStateRaw == nil)
        #expect(task.agent == nil)
    }

    @MainActor
    @Test("I7: markDone on a GTD task leaves workflowState nil and sets done/lastCompletedAt")
    func gtdMarkDoneStaysNil() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x")
        try repo.insert(task)

        try repo.markDone(task)
        #expect(task.workflowState == nil)
        #expect(task.status == .done)
        #expect(task.lastCompletedAt == now)
    }

    @MainActor
    @Test("I7: reopen on a GTD task leaves workflowState nil (no machine introduced)")
    func gtdReopenStaysNil() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x")
        try repo.insert(task)
        try repo.markDone(task)

        try repo.reopen(task)
        #expect(task.workflowState == nil)
        #expect(task.workflowStateRaw == nil)
        #expect(task.status == .open)
        #expect(task.lastCompletedAt == nil)
    }

    @MainActor
    @Test("I7: snooze/unsnooze on a GTD task is unchanged and never sets a workflow")
    func gtdSnoozeStaysNil() throws {
        var current = Self.fixedNow
        let (repo, _) = try makeRepo(now: { current })
        let task = TaskItem(title: "x")
        try repo.insert(task)

        try repo.snooze(task, until: current.addingTimeInterval(3600))
        #expect(task.status == .snoozed)
        #expect(task.workflowState == nil)

        current = current.addingTimeInterval(7200)
        try repo.unsnooze(task)
        #expect(task.status == .open)
        #expect(task.workflowState == nil)
    }

    // MARK: - I7: recurrence-spawn for a GTD task (the real I7 risk)

    @MainActor
    @Test("I7 GOLDEN: a recurring GTD task spawns a nil-workflow next occurrence")
    func gtdRecurrenceSpawnStaysNil() throws {
        let now = Self.fixedNow
        let (repo, context) = try makeRepo(now: { now })
        // No workflowState — a plain recurring GTD task.
        let task = TaskItem(title: "water plants", dueAt: now, recurrenceRule: "FREQ=DAILY")
        try repo.insert(task)

        try repo.markDone(task)

        // Old occurrence: done, still nil workflow.
        #expect(task.status == .done)
        #expect(task.workflowState == nil)

        let all = try context.fetch(FetchDescriptor<TaskItem>())
        let spawn = try #require(all.first { $0.id != task.id })
        // The spawned occurrence MUST be a GTD task too — never silently gains a
        // workflow. This is the line that guards the recurrence factory change.
        #expect(spawn.workflowState == nil)
        #expect(spawn.workflowStateRaw == nil)
        #expect(spawn.status == .open)
        #expect(spawn.dueAt == now.addingTimeInterval(86_400))
    }

    @MainActor
    @Test("I7: recurring GTD task that is reopened removes the spawn, workflow stays nil")
    func gtdRecurrenceReopenStaysNil() throws {
        let now = Self.fixedNow
        let (repo, context) = try makeRepo(now: { now })
        let task = TaskItem(title: "standup", dueAt: now, recurrenceRule: "FREQ=DAILY")
        try repo.insert(task)
        try repo.markDone(task)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 2)

        try repo.reopen(task)
        // Spawn removed; original back to open; never a workflow.
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 1)
        #expect(task.status == .open)
        #expect(task.workflowState == nil)
    }

    // MARK: - I7: existing queries unaffected by the additive fields

    @MainActor
    @Test("I7: TodayQuery/UpcomingQuery key off status, ignore workflowState")
    func gtdQueriesUnaffected() throws {
        let now = Self.fixedNow
        let (repo, context) = try makeRepo(now: { now })

        // A GTD task due today and a project task due today (workflow=todo, open).
        let gtd = TaskItem(title: "gtd today", dueAt: now)
        let project = TaskItem(title: "project today", dueAt: now, workflowState: .todo)
        try repo.insert(gtd)
        try repo.insert(project)

        let results = try TodayQuery().today(now: now).apply(in: context)
        // Both are open and due today — both appear. workflowState never gates.
        #expect(Set(results.map(\.id)) == Set([gtd.id, project.id]))
    }

    // MARK: - I8: assignedAgent has no scheduling/visibility side effects

    @MainActor
    @Test("I8: assignedAgent does not change Today membership")
    func agentNoSideEffects() throws {
        let now = Self.fixedNow
        let (repo, context) = try makeRepo(now: { now })

        let unassigned = TaskItem(title: "a", dueAt: now)
        let assigned = TaskItem(title: "b", dueAt: now, assignedAgent: .codex)
        try repo.insert(unassigned)
        try repo.insert(assigned)

        let results = try TodayQuery().today(now: now).apply(in: context)
        // Agent assignment is pure metadata — both tasks are present identically.
        #expect(Set(results.map(\.id)) == Set([unassigned.id, assigned.id]))
    }

    @MainActor
    @Test("I8: changing assignedAgent never touches status or lastCompletedAt")
    func agentMetadataOnly() throws {
        let now = Self.fixedNow
        let (repo, _) = try makeRepo(now: { now })
        let task = TaskItem(title: "x", dueAt: now)
        try repo.insert(task)
        let statusBefore = task.status

        try repo.update(task) { $0.assignedAgent = AgentAssignee.claude.rawValue }
        #expect(task.agent == .claude)
        #expect(task.status == statusBefore)
        #expect(task.lastCompletedAt == nil)
    }
}
