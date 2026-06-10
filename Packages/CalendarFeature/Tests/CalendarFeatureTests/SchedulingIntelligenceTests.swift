import Foundation
import NexusCore
import Testing

@testable import CalendarFeature

@Suite("SchedulingIntelligence")
struct SchedulingIntelligenceTests {
    // 2026-06-05 (Friday) 00:00:00 UTC — fixed absolute anchor; all offsets are
    // plain seconds so the suite is timezone- and DST-agnostic.
    private static let day = Date(timeIntervalSince1970: 1_780_617_600)

    /// Event at `hours` offsets from the fixed day anchor.
    private func event(
        _ id: String,
        from startHour: Double,
        to endHour: Double,
        allDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id,
            start: Self.day.addingTimeInterval(startHour * 3600),
            end: Self.day.addingTimeInterval(endHour * 3600),
            isAllDay: allDay
        )
    }

    private func hours(_ value: Double) -> Date {
        Self.day.addingTimeInterval(value * 3600)
    }

    // MARK: - conflicts(in:)

    @Test("Empty input yields no conflicts")
    func conflictsEmpty() {
        #expect(SchedulingIntelligence.conflicts(in: []).isEmpty)
    }

    @Test("Overlapping events conflict, with the overlap interval reported")
    func conflictsOverlap() {
        let a = event("a", from: 9, to: 11)
        let b = event("b", from: 10, to: 12)

        let conflicts = SchedulingIntelligence.conflicts(in: [a, b])

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.first.id == "a")
        #expect(conflicts.first?.second.id == "b")
        #expect(conflicts.first?.overlap == DateInterval(start: hours(10), end: hours(11)))
    }

    @Test("Touching boundaries do not conflict")
    func conflictsTouching() {
        let a = event("a", from: 9, to: 10)
        let b = event("b", from: 10, to: 11)

        #expect(SchedulingIntelligence.conflicts(in: [a, b]).isEmpty)
    }

    @Test("All-day events never conflict")
    func conflictsAllDayExcluded() {
        let allDay = event("allday", from: 0, to: 24, allDay: true)
        let timed = event("timed", from: 9, to: 10)

        #expect(SchedulingIntelligence.conflicts(in: [allDay, timed]).isEmpty)
    }

    @Test("Each unordered pair is reported once, ordered by start")
    func conflictsPairsOnce() {
        // Three mutually overlapping events → exactly 3 pairs, never 6.
        let a = event("a", from: 9, to: 12)
        let b = event("b", from: 10, to: 13)
        let c = event("c", from: 11, to: 14)

        let conflicts = SchedulingIntelligence.conflicts(in: [c, a, b])

        #expect(conflicts.count == 3)
        let pairs = conflicts.map { [$0.first.id, $0.second.id] }
        #expect(pairs == [["a", "b"], ["a", "c"], ["b", "c"]])
    }

    @Test("Identical events conflict over their full range")
    func conflictsIdenticalEvents() {
        let a = event("a", from: 9, to: 10)
        let twin = event("twin", from: 9, to: 10)

        let conflicts = SchedulingIntelligence.conflicts(in: [a, twin])

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.overlap == DateInterval(start: hours(9), end: hours(10)))
    }

    @Test("Zero-length events never conflict")
    func conflictsZeroLength() {
        let instant = event("instant", from: 9.5, to: 9.5)
        let timed = event("timed", from: 9, to: 10)

        #expect(SchedulingIntelligence.conflicts(in: [instant, timed]).isEmpty)
    }

    // MARK: - meetingLoad(events:workday:isMeeting:)

    /// 09:00–17:00 — an 8 h workday.
    private var workday: DateInterval { DateInterval(start: hours(9), end: hours(17)) }

    @Test("Empty input means zero load")
    func meetingLoadEmpty() {
        let load = SchedulingIntelligence.meetingLoad(events: [], workday: workday) { _ in true }
        #expect(load == 0)
    }

    @Test("A 2-hour meeting in an 8-hour workday is 0.25")
    func meetingLoadFraction() {
        let meeting = event("m", from: 10, to: 12)
        let load = SchedulingIntelligence.meetingLoad(events: [meeting], workday: workday) { _ in true }
        #expect(load == 0.25)
    }

    @Test("Non-meetings are excluded by the classifier")
    func meetingLoadClassifier() {
        let meeting = event("meeting", from: 10, to: 12)
        let focus = event("focus", from: 13, to: 15)
        let load = SchedulingIntelligence.meetingLoad(events: [meeting, focus], workday: workday) { $0.id == "meeting" }
        #expect(load == 0.25)
    }

    @Test("Overlapping meetings are unioned, not double-counted")
    func meetingLoadOverlapUnion() {
        // 10–12 and 11–13 union to 10–13 = 3 h of 8 h.
        let a = event("a", from: 10, to: 12)
        let b = event("b", from: 11, to: 13)
        let load = SchedulingIntelligence.meetingLoad(events: [a, b], workday: workday) { _ in true }
        #expect(load == 3.0 / 8.0)
    }

    @Test("Meetings are clipped to the workday")
    func meetingLoadClipped() {
        // 07:00–11:00 clips to 09:00–11:00 = 2 h of 8 h.
        let early = event("early", from: 7, to: 11)
        let load = SchedulingIntelligence.meetingLoad(events: [early], workday: workday) { _ in true }
        #expect(load == 0.25)
    }

    @Test("All-day events do not count toward meeting load")
    func meetingLoadAllDayExcluded() {
        let allDay = event("allday", from: 0, to: 24, allDay: true)
        let load = SchedulingIntelligence.meetingLoad(events: [allDay], workday: workday) { _ in true }
        #expect(load == 0)
    }

    @Test("A fully booked workday is exactly 1, never more")
    func meetingLoadSaturation() {
        let wall = event("wall", from: 8, to: 18)
        let extra = event("extra", from: 9, to: 17)
        let load = SchedulingIntelligence.meetingLoad(events: [wall, extra], workday: workday) { _ in true }
        #expect(load == 1)
    }

    @Test("A zero-length workday yields zero load, not a division crash")
    func meetingLoadZeroWorkday() {
        let meeting = event("m", from: 10, to: 12)
        let empty = DateInterval(start: hours(9), end: hours(9))
        let load = SchedulingIntelligence.meetingLoad(events: [meeting], workday: empty) { _ in true }
        #expect(load == 0)
    }

    // MARK: - suggestedFocusBlocks(events:within:minimumDuration:)

    @Test("An empty calendar suggests the whole workday")
    func focusBlocksEmpty() {
        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [], within: workday)
        #expect(blocks == [workday])
    }

    @Test("Gaps between events are suggested, sorted by start")
    func focusBlocksGaps() {
        // Busy 10–11 and 13–14 → free 9–10, 11–13, 14–17.
        let a = event("a", from: 10, to: 11)
        let b = event("b", from: 13, to: 14)

        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [b, a], within: workday)

        #expect(
            blocks == [
                DateInterval(start: hours(9), end: hours(10)),
                DateInterval(start: hours(11), end: hours(13)),
                DateInterval(start: hours(14), end: hours(17)),
            ]
        )
    }

    @Test("Gaps shorter than the minimum are dropped; exactly the minimum is kept")
    func focusBlocksMinimumDuration() {
        // Free 9–10 (= 1 h, kept), 10:30–11 (30 min, dropped), 11:30–17 (kept).
        let a = event("a", from: 10, to: 10.5)
        let b = event("b", from: 11, to: 11.5)

        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [a, b], within: workday)

        #expect(
            blocks == [
                DateInterval(start: hours(9), end: hours(10)),
                DateInterval(start: hours(11.5), end: hours(17)),
            ]
        )
    }

    @Test("Overlapping events merge into one busy span")
    func focusBlocksOverlappingBusy() {
        // 10–12 and 11–13 merge → free 9–10 and 13–17.
        let a = event("a", from: 10, to: 12)
        let b = event("b", from: 11, to: 13)

        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [a, b], within: workday)

        #expect(
            blocks == [
                DateInterval(start: hours(9), end: hours(10)),
                DateInterval(start: hours(13), end: hours(17)),
            ]
        )
    }

    @Test("All-day and outside-window events do not block focus time")
    func focusBlocksIgnoresAllDayAndOutside() {
        let allDay = event("allday", from: 0, to: 24, allDay: true)
        let evening = event("evening", from: 19, to: 20)

        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [allDay, evening], within: workday)

        #expect(blocks == [workday])
    }

    @Test("A maximum duration chunks long gaps into block-sized suggestions")
    func focusBlocksChunkedByMaximum() {
        // Busy 13–14 in a 9–17 workday → free 9–13 and 14–17. With a 2 h cap
        // the 4 h gap splits into 9–11 and 11–13; the 3 h gap into 14–16 and
        // a 1 h remainder 16–17 (kept: remainder ≥ the 1 h minimum).
        let a = event("a", from: 13, to: 14)

        let blocks = SchedulingIntelligence.suggestedFocusBlocks(
            events: [a],
            within: workday,
            maximumDuration: 2 * 3600
        )

        #expect(
            blocks == [
                DateInterval(start: hours(9), end: hours(11)),
                DateInterval(start: hours(11), end: hours(13)),
                DateInterval(start: hours(14), end: hours(16)),
                DateInterval(start: hours(16), end: hours(17)),
            ]
        )
    }

    @Test("Chunk remainders below the minimum are dropped")
    func focusBlocksChunkRemainderDropped() {
        // Free 9–11:30 with a 2 h cap → 9–11 plus a 30 min remainder, which
        // is below the 1 h minimum and must not be suggested.
        let a = event("a", from: 11.5, to: 17)

        let blocks = SchedulingIntelligence.suggestedFocusBlocks(
            events: [a],
            within: workday,
            maximumDuration: 2 * 3600
        )

        #expect(blocks == [DateInterval(start: hours(9), end: hours(11))])
    }

    @Test("No maximum duration keeps whole gaps (default unchanged)")
    func focusBlocksNoMaximumKeepsGaps() {
        let a = event("a", from: 13, to: 14)
        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [a], within: workday)
        #expect(
            blocks == [
                DateInterval(start: hours(9), end: hours(13)),
                DateInterval(start: hours(14), end: hours(17)),
            ]
        )
    }

    @Test("Zero-length events do not split a gap")
    func focusBlocksZeroLengthEvent() {
        let instant = event("instant", from: 12, to: 12)
        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [instant], within: workday)
        #expect(blocks == [workday])
    }

    @Test("A gap exactly equal to the minimum duration is included")
    func focusBlocksGapExactlyMinimum() {
        // Busy 10–13 in a 9–17 workday → free 9–10 is exactly 3600 s, the
        // default minimum, and must be kept (>= is inclusive).
        let busy = event("busy", from: 10, to: 13)

        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [busy], within: workday)

        #expect(
            blocks == [
                DateInterval(start: hours(9), end: hours(10)),
                DateInterval(start: hours(13), end: hours(17)),
            ]
        )
        #expect(blocks.first?.duration == 3600)
    }

    @Test("A custom minimum duration is honored")
    func focusBlocksCustomMinimum() {
        // Free 9–10 (1 h) and 11–17 (6 h); 2 h minimum keeps only the second.
        let a = event("a", from: 10, to: 11)

        let blocks = SchedulingIntelligence.suggestedFocusBlocks(events: [a], within: workday, minimumDuration: 7200)

        #expect(blocks == [DateInterval(start: hours(11), end: hours(17))])
    }

    // MARK: - timeInsights(events:week:classify:)

    /// Seven days from the anchor: Fri 2026-06-05 00:00 UTC → Fri 2026-06-12 00:00 UTC.
    private var week: DateInterval { DateInterval(start: hours(0), end: hours(7 * 24)) }

    @Test("Empty input yields empty insights")
    func insightsEmpty() {
        let insights = SchedulingIntelligence.timeInsights(events: [], week: week) { _ in .other }

        #expect(insights.totalScheduled == 0)
        for category in SchedulingIntelligence.EventCategory.allCases {
            #expect(insights.total(for: category) == 0)
        }
    }

    @Test("Totals are summed per classified category")
    func insightsPerCategory() {
        let meeting = event("meeting", from: 9, to: 10)
        let focus = event("focus", from: 10, to: 12)
        let personal = event("personal", from: 30, to: 31)  // next day

        let insights = SchedulingIntelligence.timeInsights(events: [meeting, focus, personal], week: week) { event in
            switch event.id {
            case "meeting": return .meeting
            case "focus": return .focus
            default: return .personal
            }
        }

        #expect(insights.total(for: .meeting) == 3600)
        #expect(insights.total(for: .focus) == 7200)
        #expect(insights.total(for: .personal) == 3600)
        #expect(insights.total(for: .project) == 0)
        #expect(insights.total(for: .admin) == 0)
        #expect(insights.total(for: .other) == 0)
        #expect(insights.totalScheduled == 4 * 3600)
    }

    @Test("totalScheduled is the union; per-category sums may overlap")
    func insightsOverlapUnion() {
        // 9–11 meeting overlaps 10–12 focus: categories report 2 h each,
        // but the union of scheduled time is 9–12 = 3 h.
        let meeting = event("meeting", from: 9, to: 11)
        let focus = event("focus", from: 10, to: 12)

        let insights = SchedulingIntelligence.timeInsights(events: [meeting, focus], week: week) {
            $0.id == "meeting" ? .meeting : .focus
        }

        #expect(insights.total(for: .meeting) == 2 * 3600)
        #expect(insights.total(for: .focus) == 2 * 3600)
        #expect(insights.totalScheduled == 3 * 3600)
    }

    @Test("Events are clipped to the week; outside events are dropped")
    func insightsClippedToWeek() {
        // Straddles the week start: only the inside half counts.
        let straddling = event("straddle", from: -1, to: 1)
        let outside = event("outside", from: -5, to: -3)

        let insights = SchedulingIntelligence.timeInsights(events: [straddling, outside], week: week) { _ in .meeting }

        #expect(insights.total(for: .meeting) == 3600)
        #expect(insights.totalScheduled == 3600)
    }

    @Test("All-day events are excluded from insights")
    func insightsAllDayExcluded() {
        let allDay = event("allday", from: 0, to: 24, allDay: true)
        let insights = SchedulingIntelligence.timeInsights(events: [allDay], week: week) { _ in .meeting }

        #expect(insights.total(for: .meeting) == 0)
        #expect(insights.totalScheduled == 0)
    }
}
