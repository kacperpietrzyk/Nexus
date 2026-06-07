import Foundation
import Testing

@testable import NexusCore

@Suite("DayScheduler")
struct DaySchedulerTests {
    /// Fixed-timezone calendar so window resolution is machine-independent.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// A fixed-offset estimator so the scheduler math is deterministic and the
    /// history cascade is out of scope here.
    private struct FixedEstimator: DurationEstimator {
        let seconds: Int
        func estimate(for task: TaskItem, history: [TaskItem]) -> DurationEstimate {
            DurationEstimate(seconds: seconds, confidence: 1.0)
        }
    }

    /// An estimator keyed by task title so different candidates get different
    /// durations deterministically.
    private struct TitleEstimator: DurationEstimator {
        let map: [String: Int]
        func estimate(for task: TaskItem, history: [TaskItem]) -> DurationEstimate {
            DurationEstimate(seconds: map[task.title] ?? 1800, confidence: 1.0)
        }
    }

    /// 2026-06-08 (a Monday) at 09:00 UTC.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 8) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 6,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }

    private var prefs: CalendarPreferences {
        CalendarPreferences(
            workdayStart: DateComponents(hour: 9, minute: 0),
            workdayEnd: DateComponents(hour: 18, minute: 0),
            minBlockMinutes: 15,
            maxBlockMinutes: 120,
            bufferMinutes: 0
        )
    }

    private func event(_ startHour: Int, _ endHour: Int, day: Int = 8) -> CalendarEvent {
        CalendarEvent(id: UUID().uuidString, title: "evt", start: at(startHour, day: day), end: at(endHour, day: day))
    }

    private func task(_ title: String, priority: TaskPriority = .none, order: Double? = nil) -> TaskItem {
        TaskItem(title: title, priority: priority, orderIndex: order)
    }

    private func plan(
        _ candidates: [TaskItem],
        events: [CalendarEvent] = [],
        accepted: [ScheduledBlock] = [],
        estimator: DurationEstimator,
        horizonDays: Int = 1
    ) -> SchedulePlan {
        DayScheduler().plan(
            candidates: candidates,
            events: events,
            accepted: accepted,
            prefs: prefs,
            estimator: estimator,
            now: at(9),
            calendar: calendar,
            horizonDays: horizonDays
        )
    }

    // MARK: - Slot fill

    @Test("inserts a candidate into the first free gap before an event")
    func slotFillBeforeEvent() {
        let scheduler = DayScheduler()
        let candidate = task("write report")
        let events = [event(10, 11)]  // busy 10–11, free 09–10 and 11–18
        let plan = scheduler.plan(
            candidates: [candidate],
            events: events,
            accepted: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 30 * 60),
            now: at(9),
            calendar: calendar
        )
        #expect(plan.proposals.count == 1)
        #expect(plan.proposals[0].start == at(9))
        #expect(plan.proposals[0].end == at(9, 30))
    }

    @Test("schedules around an event obstacle (no overlap)")
    func aroundEvent() {
        let scheduler = DayScheduler()
        // Two 90m tasks, event 09:30–10:30 blocks the start.
        let candidates = [task("a", priority: .high), task("b", priority: .medium)]
        let events = [CalendarEvent(id: "e", title: "evt", start: at(9, 30), end: at(10, 30))]
        let plan = scheduler.plan(
            candidates: candidates,
            events: events,
            accepted: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 30 * 60),
            now: at(9),
            calendar: calendar
        )
        // "a" first (higher priority): 09:00–09:30 (fits before event).
        #expect(plan.proposals[0].taskID == candidates[0].id)
        #expect(plan.proposals[0].start == at(9))
        #expect(plan.proposals[0].end == at(9, 30))
        // No proposal overlaps the event.
        for p in plan.proposals {
            #expect(!(p.start < at(10, 30) && p.end > at(9, 30)))
        }
    }

    // MARK: - Split

    @Test("estimate over maxBlock splits into sub-blocks")
    func splitOverMaxBlock() {
        let scheduler = DayScheduler()
        let candidate = task("big")
        // 4h estimate, maxBlock 120m → 2x 120m sub-blocks.
        let plan = scheduler.plan(
            candidates: [candidate],
            events: [],
            accepted: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 4 * 3600),
            now: at(9),
            calendar: calendar
        )
        #expect(plan.proposals.count == 2)
        #expect(plan.proposals.allSatisfy { $0.taskID == candidate.id })
        for p in plan.proposals {
            #expect(p.end.timeIntervalSince(p.start) == 120 * 60)
        }
    }

    // MARK: - Accepted untouched

    @Test("accepted blocks are hard input — never echoed, never overlapped")
    func acceptedUntouched() {
        let scheduler = DayScheduler()
        let acceptedBlock = ScheduledBlock(
            taskID: UUID(),
            start: at(9),
            end: at(11),
            status: .accepted,
            externalEventID: "evt-1"
        )
        let candidate = task("new")
        let plan = scheduler.plan(
            candidates: [candidate],
            events: [],
            accepted: [acceptedBlock],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 30 * 60),
            now: at(9),
            calendar: calendar
        )
        // Accepted not echoed.
        #expect(plan.proposals.allSatisfy { $0.taskID == candidate.id })
        // Proposal placed after the accepted block (11:00+).
        #expect(plan.proposals[0].start >= at(11))
    }

    // MARK: - Determinism

    @Test("identical input → byte-identical output (including id tiebreak)")
    func determinism() {
        // Same priority/deadline/order → only id breaks the tie.
        let candidates = (0..<5).map { _ in task("same") }
        let estimator = FixedEstimator(seconds: 30 * 60)
        let planA = plan(candidates, estimator: estimator)
        let planB = plan(candidates, estimator: estimator)
        #expect(planA == planB)
        // Order matches id-sorted candidate order.
        let expected = candidates.map(\.id).sorted { $0.uuidString < $1.uuidString }
        #expect(planA.proposals.map(\.taskID) == expected)
    }

    @Test("priority desc then deadline asc then order asc ordering")
    func orderingKeys() {
        let scheduler = DayScheduler()
        let high = task("high", priority: .high)
        let lowEarly = TaskItem(title: "lowEarly", deadlineAt: at(12), priority: .low)
        let lowLate = TaskItem(title: "lowLate", deadlineAt: at(16), priority: .low)
        let plan = scheduler.plan(
            candidates: [lowLate, high, lowEarly],
            events: [],
            accepted: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 30 * 60),
            now: at(9),
            calendar: calendar
        )
        #expect(plan.proposals.map(\.taskID) == [high.id, lowEarly.id, lowLate.id])
    }

    // MARK: - Overload

    @Test("overload report flags when work exceeds free hours")
    func overload() {
        let scheduler = DayScheduler()
        // Working window 09–18 = 9h. Three 5h tasks = 15h of work.
        let candidates = [task("a"), task("b"), task("c")]
        let plan = scheduler.plan(
            candidates: candidates,
            events: [],
            accepted: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 5 * 3600),
            now: at(9),
            calendar: calendar
        )
        #expect(plan.overload.isOverloaded)
        #expect(plan.overload.totalEstimatedSeconds == 15 * 3600)
        #expect(plan.overload.totalFreeSeconds == 9 * 3600)
        #expect(!plan.overload.unplacedTaskIDs.isEmpty)
    }

    @Test("not overloaded when work fits")
    func notOverloaded() {
        let scheduler = DayScheduler()
        let plan = scheduler.plan(
            candidates: [task("a"), task("b")],
            events: [],
            accepted: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 60 * 60),
            now: at(9),
            calendar: calendar
        )
        #expect(!plan.overload.isOverloaded)
        #expect(plan.overload.unplacedTaskIDs.isEmpty)
    }

    // MARK: - Multi-day horizon

    @Test("horizon=1 is today-only (regression baseline)")
    func horizonOneTodayOnly() {
        let scheduler = DayScheduler()
        // 12h of work, 9h today → 3h unplaced with horizon=1.
        let candidate = task("huge")
        let plan = scheduler.plan(
            candidates: [candidate],
            events: [],
            accepted: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 12 * 3600),
            now: at(9),
            calendar: calendar,
            horizonDays: 1
        )
        // All proposals are on day 8.
        #expect(plan.proposals.allSatisfy { calendar.component(.day, from: $0.start) == 8 })
        // Some work did not fit today.
        #expect(plan.overload.unplacedTaskIDs.contains(candidate.id))
    }

    @Test("horizon>1 spills sub-blocks onto subsequent working days")
    func horizonSpill() {
        let scheduler = DayScheduler()
        let candidate = task("huge")
        let plan = scheduler.plan(
            candidates: [candidate],
            events: [],
            accepted: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 12 * 3600),
            now: at(9),
            calendar: calendar,
            horizonDays: 2
        )
        let days = Set(plan.proposals.map { calendar.component(.day, from: $0.start) })
        // Spilled onto day 8 and day 9.
        #expect(days.contains(8))
        #expect(days.contains(9))
        // With 18h capacity across 2 days, 12h fits — nothing unplaced.
        #expect(plan.overload.unplacedTaskIDs.isEmpty)
    }

    @Test("horizon>1 keeps determinism")
    func horizonDeterminism() {
        let candidates = (0..<4).map { i in task("t\(i)") }
        let estimator = TitleEstimator(map: ["t0": 5 * 3600, "t1": 5 * 3600, "t2": 5 * 3600, "t3": 5 * 3600])
        let a = plan(candidates, estimator: estimator, horizonDays: 3)
        let b = plan(candidates, estimator: estimator, horizonDays: 3)
        #expect(a == b)
    }
}
