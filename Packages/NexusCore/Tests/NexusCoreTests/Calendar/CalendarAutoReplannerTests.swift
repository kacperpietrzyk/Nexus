import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("CalendarAutoReplanner")
@MainActor
struct CalendarAutoReplannerTests {
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

    // 2026-06-08 09:00 UTC — inside the default 09:00–18:00 working window.
    private let now = Date(timeIntervalSince1970: 1_780_650_000)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        now.addingTimeInterval(TimeInterval((hour - 9) * 3600 + minute * 60))
    }

    private func openTask(_ context: ModelContext, title: String) throws -> TaskItem {
        let task = TaskItem(title: title, dueAt: now.addingTimeInterval(3600))
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()
        return task
    }

    private func event(_ id: String, _ start: Date, _ end: Date) -> CalendarEvent {
        CalendarEvent(id: id, title: "evt", start: start, end: end)
    }

    @Test("an event landing on an auto proposal regenerates proposals around it")
    func regeneratesConflictedProposals() async throws {
        let context = try makeContext()
        let task = try openTask(context, title: "write")
        let planner = DayPlanner(context: context)
        _ = try planner.planDay(events: [], prefs: .default, now: now, calendar: calendar)
        // Proposal sits at 09:00–09:30 (empty day, window opens at 09:00).

        let writer = MockCalendarWriter()
        let replanner = CalendarAutoReplanner(
            context: context,
            reconciler: CalendarSyncReconciler(context: context, writer: writer, now: { self.now })
        )
        let outcome = try await replanner.handleStoreChange(
            events: [event("ext-1", at(9), at(10))],
            prefs: .default,
            now: now,
            calendar: calendar
        )

        #expect(outcome.replanned)
        #expect(!outcome.report.hasConflicts)
        let live = try ScheduledBlockRepository(context: context).blocks(from: at(9), to: at(18))
        let proposals = live.filter { $0.status == .proposed }
        #expect(proposals.count == 1)
        #expect(proposals.first?.taskID == task.id)
        #expect(proposals.first?.start == at(10))
    }

    @Test("an event landing on an accepted block reports it and never moves it")
    func acceptedConflictReportedNotMoved() async throws {
        let context = try makeContext()
        let writer = MockCalendarWriter()
        let calendarID = try await writer.ensureNexusCalendar()
        let mirrorID = try await writer.createEvent(
            EventDraft(calendarID: calendarID, title: "deep work", start: at(13), end: at(14))
        )
        let repo = ScheduledBlockRepository(context: context)
        let accepted = try repo.create(
            taskID: UUID(),
            start: at(13),
            end: at(14),
            title: "deep work",
            status: .accepted,
            externalEventID: mirrorID
        )

        let replanner = CalendarAutoReplanner(
            context: context,
            reconciler: CalendarSyncReconciler(context: context, writer: writer, now: { self.now })
        )
        let outcome = try await replanner.handleStoreChange(
            events: [
                event(mirrorID, at(13), at(14)),
                event("ext-2", at(13, 30), at(14, 30)),
            ],
            prefs: .default,
            now: now,
            calendar: calendar
        )

        #expect(!outcome.replanned)
        #expect(outcome.report.protectedBlockIDs == [accepted.id])
        #expect(accepted.start == at(13))
        #expect(accepted.end == at(14))
        #expect(accepted.deletedAt == nil)
    }

    @Test("no conflicts means no replan churn — the existing proposal survives untouched")
    func noConflictNoChurn() async throws {
        let context = try makeContext()
        _ = try openTask(context, title: "write")
        let planner = DayPlanner(context: context)
        let first = try planner.planDay(events: [], prefs: .default, now: now, calendar: calendar)
        let originalID = try #require(first.proposals.first?.id)

        let replanner = CalendarAutoReplanner(context: context, reconciler: nil)
        let outcome = try await replanner.handleStoreChange(
            events: [event("ext-1", at(15), at(16))],
            prefs: .default,
            now: now,
            calendar: calendar
        )

        #expect(!outcome.replanned)
        #expect(!outcome.report.hasConflicts)
        let live = try ScheduledBlockRepository(context: context).blocks(from: at(9), to: at(18))
        #expect(live.contains { $0.id == originalID })
    }

    @Test("a store change never initiates planning when no plan exists")
    func neverInitiatesPlanning() async throws {
        let context = try makeContext()
        _ = try openTask(context, title: "write")  // candidate exists, but no plan was ever made
        let replanner = CalendarAutoReplanner(context: context, reconciler: nil)
        let outcome = try await replanner.handleStoreChange(
            events: [event("ext-1", at(9), at(10))],
            prefs: .default,
            now: now,
            calendar: calendar
        )
        #expect(!outcome.replanned)
        let live = try ScheduledBlockRepository(context: context).blocks(from: at(9), to: at(18))
        #expect(live.isEmpty)
    }

    @Test("an externally moved mirror event is reconciled first, then proposals regenerate")
    func reconcileThenReplan() async throws {
        let context = try makeContext()
        let task = try openTask(context, title: "write")
        let writer = MockCalendarWriter()
        let calendarID = try await writer.ensureNexusCalendar()
        let mirrorID = try await writer.createEvent(
            EventDraft(calendarID: calendarID, title: "deep work", start: at(11), end: at(12))
        )
        let repo = ScheduledBlockRepository(context: context)
        let accepted = try repo.create(
            taskID: UUID(),
            start: at(11),
            end: at(12),
            title: "deep work",
            status: .accepted,
            externalEventID: mirrorID
        )
        let planner = DayPlanner(context: context)
        _ = try planner.planDay(events: [], prefs: .default, now: now, calendar: calendar)
        // Proposal sits at 09:00–09:30; the accepted block occupies 11:00–12:00.

        // The user drags the mirror event onto the proposal's slot in Apple Calendar.
        try await writer.updateEvent(
            id: mirrorID,
            with: EventDraft(calendarID: calendarID, title: "deep work", start: at(9), end: at(10))
        )

        let replanner = CalendarAutoReplanner(
            context: context,
            reconciler: CalendarSyncReconciler(context: context, writer: writer, now: { self.now })
        )
        let outcome = try await replanner.handleStoreChange(
            events: [event(mirrorID, at(9), at(10))],
            prefs: .default,
            now: now,
            calendar: calendar
        )

        // External edit applied to the accepted block first (read-back wins)…
        #expect(accepted.start == at(9))
        #expect(accepted.end == at(10))
        // …and the broken proposal regenerated after the new obstacle.
        #expect(outcome.replanned)
        let proposals = try repo.blocks(from: at(9), to: at(18)).filter { $0.status == .proposed }
        #expect(proposals.count == 1)
        #expect(proposals.first?.taskID == task.id)
        #expect(proposals.first?.start == at(10))
    }
}
