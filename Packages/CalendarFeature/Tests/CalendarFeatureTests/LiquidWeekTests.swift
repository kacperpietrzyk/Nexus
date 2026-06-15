import Foundation
import NexusCore
import NexusUI
import Testing

@testable import CalendarFeature

/// Pure logic added for the liquid Week module: grid snap math, the shared
/// event classifier, and the week-scope intelligence aggregations.
@Suite("Liquid Week")
struct LiquidWeekTests {

    /// Fixed UTC calendar so workday/weekend math is machine-independent.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    // 2026-06-08 (Monday) 00:00:00 UTC.
    private static let monday = Date(timeIntervalSince1970: 1_780_876_800)

    /// Mon–Sun of the fixed week.
    private static let weekDays: [Date] = (0..<7).map { offset in
        monday.addingTimeInterval(Double(offset) * 86_400)
    }

    private func date(day dayOffset: Int = 0, hours: Double) -> Date {
        Self.monday.addingTimeInterval(Double(dayOffset) * 86_400 + hours * 3600)
    }

    private func event(
        _ id: String,
        day dayOffset: Int = 0,
        from startHour: Double,
        to endHour: Double,
        allDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id,
            start: date(day: dayOffset, hours: startHour),
            end: date(day: dayOffset, hours: endHour),
            isAllDay: allDay
        )
    }

    // MARK: - WeekGridMath

    @Test("y → minutes snaps to the 15-minute grid")
    func snapBasics() {
        // hourHeight 60 → 1 pt per minute.
        #expect(WeekGridMath.snappedMinutes(forY: 0, hourHeight: 60) == 0)
        #expect(WeekGridMath.snappedMinutes(forY: 60, hourHeight: 60) == 60)
        // 72.5 min rounds to 75.
        #expect(WeekGridMath.snappedMinutes(forY: 72.5, hourHeight: 60) == 75)
        // 67 min rounds down to 60.
        #expect(WeekGridMath.snappedMinutes(forY: 67, hourHeight: 60) == 60)
    }

    @Test("Snapping clamps inside the day")
    func snapClamps() {
        #expect(WeekGridMath.snappedMinutes(forY: -50, hourHeight: 60) == 0)
        // Beyond the bottom edge clamps to the last 15-min slot.
        #expect(WeekGridMath.snappedMinutes(forY: 10_000, hourHeight: 60) == 24 * 60 - 15)
    }

    @Test("Snapping scales with hour height")
    func snapScalesWithHourHeight() {
        // hourHeight 120 → 0.5 min per pt: y=120 is exactly 1 hour.
        #expect(WeekGridMath.snappedMinutes(forY: 120, hourHeight: 120) == 60)
    }

    @Test("snappedDate composes the day start with the snapped offset")
    func snappedDateComposition() {
        let dropped = WeekGridMath.snappedDate(
            forY: 9.25 * 60,  // 09:15 at 60 pt/hour
            day: date(hours: 13),  // any instant inside the day
            calendar: Self.calendar,
            hourHeight: 60
        )
        #expect(dropped == date(hours: 9.25))
    }

    @Test("yOffset is the inverse of the minute axis")
    func yOffsetInverse() {
        #expect(WeekGridMath.yOffset(forMinutes: 90, hourHeight: 60) == 90)
        #expect(WeekGridMath.yOffset(forMinutes: 0, hourHeight: 60) == 0)
    }

    // MARK: - WeekEditorTarget (Mac create path)

    @Test("createSeed builds a default-duration draft on no system calendar")
    func createSeedShape() {
        let start = date(hours: 9)
        let seed = WeekEditorTarget.createSeed(at: start)
        #expect(seed.calendarID == nil)
        #expect(seed.title.isEmpty)
        #expect(seed.start == start)
        #expect(seed.end == start.addingTimeInterval(WeekGridMetrics.defaultBlockDuration))
        #expect(seed.recurrence == nil)
    }

    @Test("createSeed honors a custom duration")
    func createSeedCustomDuration() {
        let start = date(hours: 14)
        let seed = WeekEditorTarget.createSeed(at: start, duration: 1800)
        #expect(seed.end == start.addingTimeInterval(1800))
    }

    @Test("Create and edit targets carry distinct stable ids")
    func editorTargetIdentity() {
        let edit = WeekEditorTarget.edit("evt-42")
        #expect(edit.id == "edit-evt-42")
        #expect(edit.mode == .edit(eventID: "evt-42"))

        // Each create presentation is uniquely identified so re-tapping "+"
        // re-presents the sheet rather than being deduped by `sheet(item:)`.
        let firstCreate = WeekEditorTarget.create()
        let secondCreate = WeekEditorTarget.create()
        #expect(firstCreate.id != secondCreate.id)
        #expect(firstCreate.mode == .create(seed: nil))

        let seeded = WeekEditorTarget.create(seed: WeekEditorTarget.createSeed(at: date(hours: 10)))
        if case .create(let seed) = seeded.mode {
            #expect(seed?.start == date(hours: 10))
        } else {
            Issue.record("Expected a create mode with a seed")
        }
    }

    // MARK: - WeekEventClassifier

    @Test("Grid items classify exactly like the Today agenda: events → meeting, blocks → focus")
    func classifierKinds() {
        let eventItem = TimelineItem(
            id: "event-x", title: "x", start: date(hours: 9), end: date(hours: 10), kind: .event
        )
        let proposed = TimelineItem(
            id: "block-a", title: "a", start: date(hours: 9), end: date(hours: 10),
            kind: .proposedBlock, blockID: UUID()
        )
        let accepted = TimelineItem(
            id: "block-b", title: "b", start: date(hours: 9), end: date(hours: 10),
            kind: .acceptedBlock, blockID: UUID()
        )
        #expect(WeekEventClassifier.kind(for: eventItem) == .meeting)
        #expect(WeekEventClassifier.kind(for: proposed) == .focus)
        #expect(WeekEventClassifier.kind(for: accepted) == .focus)
    }

    @Test("Mirror events of accepted blocks categorize as focus, others as meeting")
    func classifierCategories() {
        let mirror = event("mirror", from: 9, to: 10)
        let external = event("external", from: 11, to: 12)
        let mirrored: Set<String> = ["mirror"]
        #expect(WeekEventClassifier.category(for: mirror, mirroredEventIDs: mirrored) == .focus)
        #expect(WeekEventClassifier.category(for: external, mirroredEventIDs: mirrored) == .meeting)
    }

    // MARK: - Duration clamp

    @Test("clampDuration defaults to 1h, floors at one snap step, and caps at the gap")
    func clampDuration() {
        let gap = DateInterval(start: date(hours: 9), duration: 2 * 3600)
        // No estimate → the 1 h default.
        #expect(WeekUnscheduledLoader.clampDuration(estimate: nil, gap: gap) == 3600)
        // Tiny estimate floors at one 15-min snap step.
        #expect(WeekUnscheduledLoader.clampDuration(estimate: 60, gap: gap) == 15 * 60)
        // Oversized estimate caps at the gap.
        #expect(WeekUnscheduledLoader.clampDuration(estimate: 10 * 3600, gap: gap) == 2 * 3600)
    }

    // MARK: - Error copy

    @Test("Provider errors surface their user-facing message, not the enum debug shape")
    func errorMessageHumanized() {
        #expect(
            CalendarViewModel.errorMessage(
                CalendarProviderError.underlying("No writable calendar source available")
            ) == "No writable calendar source available"
        )
        #expect(
            CalendarViewModel.errorMessage(CalendarProviderError.accessDenied)
                == "Calendar access was denied."
        )
    }

    // MARK: - WeekIntelligence

    @Test("Workday window spans 8 AM – 6 PM")
    func workdayWindow() {
        let window = WeekIntelligence.workdayWindow(for: Self.monday, calendar: Self.calendar)
        #expect(window == DateInterval(start: date(hours: 8), end: date(hours: 18)))
    }

    @Test("Week meeting load aggregates workdays and skips weekends")
    func weekMeetingLoadAggregates() {
        // One 1 h meeting on Monday; 5 workdays × 10 h = 50 h denominator.
        let load = WeekIntelligence.weekMeetingLoad(
            events: [event("m", from: 9, to: 10)],
            days: Self.weekDays,
            calendar: Self.calendar,
            mirroredEventIDs: []
        )
        #expect(abs(load - 1.0 / 50.0) < 0.0001)

        // The same hour on Saturday counts for nothing.
        let weekendLoad = WeekIntelligence.weekMeetingLoad(
            events: [event("m", day: 5, from: 9, to: 10)],
            days: Self.weekDays,
            calendar: Self.calendar,
            mirroredEventIDs: []
        )
        #expect(weekendLoad == 0)
    }

    @Test("Mirrored focus events do not count toward meeting load")
    func weekMeetingLoadExcludesMirrors() {
        let load = WeekIntelligence.weekMeetingLoad(
            events: [event("mirror", from: 9, to: 17)],
            days: Self.weekDays,
            calendar: Self.calendar,
            mirroredEventIDs: ["mirror"]
        )
        #expect(load == 0)
    }

    @Test("Today's focus gaps clamp to now and skip weeks not containing today")
    func todayFocusGaps() {
        let now = date(hours: 10)  // Monday 10:00
        let gaps = WeekIntelligence.todayFocusGaps(
            events: [event("m", from: 12, to: 13)],
            days: Self.weekDays,
            calendar: Self.calendar,
            now: now
        )
        // Free 10–12 and 13–18, chunked into ≤2 h suggestions (the 13–18 gap
        // splits 13–15 / 15–17 / 17–18).
        #expect(
            gaps == [
                DateInterval(start: date(hours: 10), end: date(hours: 12)),
                DateInterval(start: date(hours: 13), end: date(hours: 15)),
                DateInterval(start: date(hours: 15), end: date(hours: 17)),
                DateInterval(start: date(hours: 17), end: date(hours: 18)),
            ]
        )

        // A visible week that does not contain "today" yields nothing.
        let otherWeek = (7..<14).map { Self.monday.addingTimeInterval(Double($0) * 86_400) }
        let none = WeekIntelligence.todayFocusGaps(
            events: [],
            days: otherWeek,
            calendar: Self.calendar,
            now: now
        )
        #expect(none.isEmpty)
    }

    @Test("nextFitGap finds the first slot that fits, rolling into later days")
    func nextFitGapRolls() {
        // Monday fully booked 8–18 → the 2 h event must land Tuesday 8–10.
        let busyMonday = event("busy", from: 8, to: 18)
        let gap = WeekIntelligence.nextFitGap(
            after: date(hours: 9),
            duration: 2 * 3600,
            events: [busyMonday],
            days: Self.weekDays,
            calendar: Self.calendar
        )
        #expect(gap == DateInterval(start: date(day: 1, hours: 8), duration: 2 * 3600))
    }

    @Test("nextFitGap returns nil when nothing fits in the week")
    func nextFitGapNone() {
        // Every workday fully booked.
        let busy = (0..<5).map { event("busy-\($0)", day: $0, from: 8, to: 18) }
        let gap = WeekIntelligence.nextFitGap(
            after: Self.monday,
            duration: 3600,
            events: busy,
            days: Self.weekDays,
            calendar: Self.calendar
        )
        #expect(gap == nil)
    }

    @Test("series previews classify as focus blocks on the week grid")
    func seriesPreviewClassifiesAsFocus() {
        let item = TimelineItem(
            id: "series-x",
            title: "standup",
            start: date(day: 1, hours: 9),
            end: date(day: 1, hours: 10),
            kind: .seriesPreview
        )
        #expect(WeekEventClassifier.kind(for: item) == .focus)
    }

    @MainActor
    @Test("Reference week snapshot supplies dense calendar data without persistence")
    func referenceSnapshotDensity() {
        let snapshot = LiquidWeekReferenceData.snapshot(
            days: Self.weekDays,
            now: date(day: 4, hours: 13.65),
            calendar: Self.calendar
        )
        let items = snapshot.itemsByDay.values.flatMap { $0 }
        #expect(snapshot.days.count == 7)
        #expect(items.count >= 10)
        #expect(items.contains { $0.isAllDay })
        #expect(snapshot.unscheduledTasks.count >= 4)
        #expect(snapshot.focusGaps.count >= 2)
        #expect(SchedulingIntelligence.conflicts(in: snapshot.events).isEmpty == false)
    }
}
