import Foundation
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("CycleStatsModel")
struct CycleStatsModelTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let hour: TimeInterval = 3_600

    @MainActor
    @Test("stats counts live non-template tasks, done, and scope creep (createdAt after startAt)")
    func statsCounts() {
        let planned = TaskItem(title: "Planned")
        planned.createdAt = Self.start.addingTimeInterval(-Self.hour)
        let creep = TaskItem(title: "Creep")
        creep.createdAt = Self.start.addingTimeInterval(Self.hour)
        let done = TaskItem(title: "Done", status: .done)
        done.createdAt = Self.start.addingTimeInterval(-Self.hour)
        let deleted = TaskItem(title: "Deleted")
        deleted.deletedAt = Self.start
        let template = TaskItem(title: "Template")
        template.isTemplate = true

        let stats = CycleStatsModel.stats(
            tasks: [planned, creep, done, deleted, template],
            cycleStartAt: Self.start
        )

        #expect(stats.total == 3)
        #expect(stats.done == 1)
        #expect(stats.open == 2)
        #expect(stats.addedAfterStart == 1)
        #expect(abs(stats.completionFraction - 1.0 / 3.0) < 0.000_1)
    }

    @MainActor
    @Test("completionFraction is 0 for an empty cycle (no division by zero)")
    func emptyFraction() {
        let stats = CycleStatsModel.stats(tasks: [], cycleStartAt: Self.start)
        #expect(stats.total == 0)
        #expect(stats.completionFraction == 0)
    }

    @Test("endOfCyclePrompt fires only for an ended, still-active cycle with open tasks")
    func promptGating() {
        let endAt = Self.start
        let after = Self.start.addingTimeInterval(Self.hour)
        let before = Self.start.addingTimeInterval(-Self.hour)
        let nextID = UUID()

        let prompt = CycleStatsModel.endOfCyclePrompt(
            status: .active, endAt: endAt, now: after, openCount: 3,
            nextCycleID: nextID, nextCycleName: "Sprint 13"
        )
        #expect(
            prompt
                == CycleStatsModel.EndOfCyclePrompt(openCount: 3, nextCycleID: nextID, nextCycleName: "Sprint 13"))

        // Not ended yet.
        #expect(
            CycleStatsModel.endOfCyclePrompt(
                status: .active, endAt: endAt, now: before, openCount: 3,
                nextCycleID: nextID, nextCycleName: "Sprint 13"
            ) == nil)
        // Already completed.
        #expect(
            CycleStatsModel.endOfCyclePrompt(
                status: .completed, endAt: endAt, now: after, openCount: 3,
                nextCycleID: nextID, nextCycleName: "Sprint 13"
            ) == nil)
        // Upcoming (never started) — nothing to roll over.
        #expect(
            CycleStatsModel.endOfCyclePrompt(
                status: .upcoming, endAt: endAt, now: after, openCount: 3,
                nextCycleID: nextID, nextCycleName: "Sprint 13"
            ) == nil)
        // Nothing open.
        #expect(
            CycleStatsModel.endOfCyclePrompt(
                status: .active, endAt: endAt, now: after, openCount: 0,
                nextCycleID: nextID, nextCycleName: "Sprint 13"
            ) == nil)
        // No next cycle — prompt still fires (the view offers guidance instead of the move button).
        let withoutNext = CycleStatsModel.endOfCyclePrompt(
            status: .active, endAt: endAt, now: after, openCount: 1,
            nextCycleID: nil, nextCycleName: nil
        )
        #expect(withoutNext?.openCount == 1)
        #expect(withoutNext?.nextCycleID == nil)
    }

    @MainActor
    @Test("planning view and stats header construct for any cycle")
    func planningSurfacesConstruct() {
        let cycle = Cycle(
            name: "Sprint",
            startAt: Self.start,
            endAt: Self.start.addingTimeInterval(14 * 86_400)
        )
        _ = CyclePlanningView(cycle: cycle)
        _ = CycleStatsHeader(stats: CycleStatsModel.Stats(total: 3, done: 1, addedAfterStart: 1))
    }
}
