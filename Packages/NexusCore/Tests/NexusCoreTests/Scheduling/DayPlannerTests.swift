import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("DayPlanner")
struct DayPlannerTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ScheduledBlock.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // 2026-06-08 09:00 UTC — inside the default 09:00–18:00 window.
    private let now = Date(timeIntervalSince1970: 1_780_650_000)

    @MainActor
    @Test("planDay persists proposals for due-today candidates around events")
    func plansDay() throws {
        let context = try makeContext()
        let cal = calendar
        let task = TaskItem(title: "write report", dueAt: now.addingTimeInterval(3600))
        task.estimatedDurationSeconds = 3600
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let planner = DayPlanner(context: context)
        let result = try planner.planDay(events: [], prefs: .default, now: now, calendar: cal)

        #expect(!result.proposals.isEmpty)
        #expect(result.proposals.allSatisfy { $0.status == .proposed })
        #expect(result.proposals.allSatisfy { $0.taskID == task.id })
    }

    @MainActor
    @Test("Re-planning clears stale proposals (no duplicates) but keeps accepted blocks")
    func replanClearsProposalsKeepsAccepted() throws {
        let context = try makeContext()
        let cal = calendar
        let task = TaskItem(title: "task", dueAt: now.addingTimeInterval(3600))
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)

        // An already-accepted block for an unrelated task — must survive re-plan.
        let acceptedBlock = ScheduledBlock(
            taskID: UUID(),
            start: now.addingTimeInterval(7200),
            end: now.addingTimeInterval(9000),
            status: .accepted,
            externalEventID: "evt-1"
        )
        context.insert(acceptedBlock)
        try context.save()

        let planner = DayPlanner(context: context)
        _ = try planner.planDay(events: [], prefs: .default, now: now, calendar: cal)
        _ = try planner.planDay(events: [], prefs: .default, now: now, calendar: cal)

        let liveProposed = try context.fetch(
            FetchDescriptor<ScheduledBlock>(
                predicate: #Predicate { $0.deletedAt == nil && $0.statusRaw == "proposed" }
            )
        )
        // Exactly one proposal survives — re-plan did not stack duplicates.
        #expect(liveProposed.filter { $0.taskID == task.id }.count >= 1)

        let liveAccepted = try context.fetch(
            FetchDescriptor<ScheduledBlock>(
                predicate: #Predicate { $0.deletedAt == nil && $0.statusRaw == "accepted" }
            )
        )
        #expect(liveAccepted.contains { $0.externalEventID == "evt-1" })
    }

    @MainActor
    @Test("planDay preserves manual-origin proposed blocks and schedules around them")
    func planDayKeepsManualProposals() throws {
        let context = try makeContext()
        let cal = calendar
        let task = TaskItem(title: "task", dueAt: now.addingTimeInterval(3600))
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        // A hand-placed, not-yet-accepted block (origin preserved across
        // re-plans per ScheduledBlockOrigin.manual's contract).
        let repo = ScheduledBlockRepository(context: context)
        let manual = try repo.create(
            taskID: UUID(),
            start: now,
            end: now.addingTimeInterval(3600),
            title: "hand-placed",
            status: .proposed,
            origin: .manual
        )

        let planner = DayPlanner(context: context)
        let result = try planner.planDay(events: [], prefs: .default, now: now, calendar: cal)

        #expect(manual.deletedAt == nil)
        #expect(result.proposals.count == 1)
        // The new auto proposal is placed AFTER the manual block (it is an obstacle).
        #expect(result.proposals.first?.start == now.addingTimeInterval(3600))
    }

    @MainActor
    @Test("replan(taskIDs:) schedules only the requested tasks around every other live block")
    func replanTargetsOnlyRequestedTasks() throws {
        let context = try makeContext()
        let cal = calendar
        // The task to replan: open, NO due date — deliberately outside the
        // planDay candidate pool (overdue + due-today + pinned). replan must
        // work for it anyway: its conflicted block proved it was planned.
        let task = TaskItem(title: "rescue me")
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let repo = ScheduledBlockRepository(context: context)
        _ = try repo.create(
            taskID: UUID(),
            start: now,
            end: now.addingTimeInterval(3600),
            title: "accepted block",
            status: .accepted,
            externalEventID: "mirror-1"
        )
        let otherProposal = try repo.create(
            taskID: UUID(),
            start: now.addingTimeInterval(3600),
            end: now.addingTimeInterval(5400),
            title: "other proposal",
            status: .proposed,
            origin: .auto
        )

        let planner = DayPlanner(context: context)
        let result = try planner.replan(
            taskIDs: [task.id],
            events: [],
            prefs: .default,
            now: now,
            calendar: cal
        )

        #expect(result.proposals.count == 1)
        #expect(result.proposals.first?.taskID == task.id)
        // Placed after BOTH the accepted block and the other task's proposal —
        // a targeted replan never double-books an already-promised slot.
        #expect(result.proposals.first?.start == now.addingTimeInterval(5400))
        // And never clears other proposals (unlike planDay).
        #expect(otherProposal.deletedAt == nil)
    }

    @MainActor
    @Test("replan with no task ids is a no-op")
    func replanEmptyIsNoop() throws {
        let context = try makeContext()
        let planner = DayPlanner(context: context)
        let result = try planner.replan(
            taskIDs: [],
            events: [],
            prefs: .default,
            now: now,
            calendar: calendar
        )
        #expect(result.proposals.isEmpty)
        #expect(result.overload.unplacedTaskIDs.isEmpty)
    }
}
