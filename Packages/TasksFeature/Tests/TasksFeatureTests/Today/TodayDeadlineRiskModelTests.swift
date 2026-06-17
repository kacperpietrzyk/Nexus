import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("TodayDeadlineRiskModel skip-redundant-reload gate")
@MainActor
struct TodayDeadlineRiskModelTests {

    /// In-memory store seeded with an open task carrying a near-term deadline so
    /// the projection has real work to do (and so the produced summary is a
    /// non-trivial value the equivalence test can compare).
    private func makeGateContext() throws -> (ModelContext, Date) {
        let container = try ModelContainer(
            for: TaskItem.self, Link.self, Project.self, Note.self, ScheduledBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let now = Date.now
        let task = TaskItem(title: "ship the thing", dueAt: now.addingTimeInterval(60 * 60))
        context.insert(task)
        try context.save()
        return (context, now)
    }

    private func refreshGate(
        _ model: TodayDeadlineRiskModel,
        _ context: ModelContext,
        calendarEventsEnabled: Bool = false,
        now: Date
    ) async {
        await model.refresh(
            modelContext: context,
            calendarProvider: MockCalendarEventProvider(status: .denied),
            calendarEventsEnabled: calendarEventsEnabled,
            now: now
        )
    }

    @Test("Second refresh, same day + clean dirty flag, does NOT recompute the projection")
    func skipRedundantRefresh() async throws {
        let (context, now) = try makeGateContext()
        let model = TodayDeadlineRiskModel()

        await refreshGate(model, context, now: now)
        #expect(model.deadlineRiskComputeCount == 1)
        let firstSummary = model.summary

        // Return-navigation: same day, no change -> early return, no recompute.
        await refreshGate(model, context, now: now)
        #expect(model.deadlineRiskComputeCount == 1)
        #expect(model.summary == firstSummary)
    }

    @Test("markDirty forces the next refresh to recompute")
    func markDirtyForcesRefresh() async throws {
        let (context, now) = try makeGateContext()
        let model = TodayDeadlineRiskModel()

        await refreshGate(model, context, now: now)
        #expect(model.deadlineRiskComputeCount == 1)

        model.markDirty()
        await refreshGate(model, context, now: now)
        #expect(model.deadlineRiskComputeCount == 2)
    }

    @Test("Day rollover forces the next refresh to recompute")
    func dayRolloverForcesRefresh() async throws {
        let (context, now) = try makeGateContext()
        let model = TodayDeadlineRiskModel()

        await refreshGate(model, context, now: now)
        #expect(model.deadlineRiskComputeCount == 1)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        await refreshGate(model, context, now: tomorrow)
        #expect(model.deadlineRiskComputeCount == 2)
    }

    @Test("Changing calendarEventsEnabled forces the next refresh to recompute")
    func calendarToggleForcesRefresh() async throws {
        let (context, now) = try makeGateContext()
        let model = TodayDeadlineRiskModel()

        await refreshGate(model, context, calendarEventsEnabled: false, now: now)
        #expect(model.deadlineRiskComputeCount == 1)

        // Same day, clean flag, but calendar toggle flips -> must recompute.
        await refreshGate(model, context, calendarEventsEnabled: true, now: now)
        #expect(model.deadlineRiskComputeCount == 2)
    }

    @Test("Gate preserves the exact summary an un-gated projection produces (pixel-identity)")
    func gateSummaryIsIdentical() async throws {
        let (context, now) = try makeGateContext()

        // Canonical un-gated projection, computed inline exactly as the model
        // does, to prove the gated model's held value is byte-for-byte that.
        let risks = DeadlineRiskProjector.project(
            context: context,
            events: [],
            prefs: UserDefaultsCalendarPreferencesStore().load(),
            horizon: TimeInterval(TodayDeadlineRiskModel.horizonDays * 24 * 60 * 60),
            now: now,
            calendar: .current
        )
        let expected = DeadlineRiskSummary.make(from: risks)

        // A model refreshed twice (second is gated) must still hold the
        // canonical summary, and must have computed exactly once.
        let gated = TodayDeadlineRiskModel()
        await refreshGate(gated, context, now: now)
        await refreshGate(gated, context, now: now)

        #expect(gated.summary == expected)
        #expect(gated.deadlineRiskComputeCount == 1)
    }
}
