import Foundation
import NexusCore
import Testing

@testable import TasksFeature

/// Coverage for the embedded-Today DayTimeline geometry
/// (`TodayDashboard.embeddedTimelineBlocks` + `embeddedFreeTimeLabel` +
/// `embeddedTimelineAccessibilityLabels`). The rail is a SCROLLABLE full-day
/// (0–24) timeline: no item is ever dropped for falling outside a visible
/// sub-window, and all-day events are routed to a separate strip rather than
/// placed on the hour axis. Mirrors the `ScheduleGroupingTests` idiom: fixed
/// UTC gregorian calendar, deterministic component-built dates, Swift Testing
/// `@Test`/`#expect`.
///
/// `@MainActor` on the suite: `embeddedTimelineBlocks` /
/// `embeddedFreeTimeLabel` are statics on `TodayDashboard`, a SwiftUI
/// `View` (`@MainActor`-isolated under Swift 6 strict concurrency).
/// Calling them from a `nonisolated` test context is an actor-isolation
/// violation that traps the test runner at runtime — the same idiom
/// `TodayDashboardTests` uses for its `TodayDashboard.scheduleTasks(...)`
/// test (per-test `@MainActor`), hoisted to the suite here since every
/// case touches a `TodayDashboard` static.
@Suite("EmbeddedTimelineBlocks")
@MainActor
struct EmbeddedTimelineBlocksTests {

    // MARK: - Block geometry (via embeddedTimelineBlocks)

    @Test("nil/zero endAt yields a synthetic >=15-minute span, never degenerate")
    func syntheticSpanForMissingOrZeroEnd() throws {
        let calendar = TimelineFixture.utcCalendar
        let start = TimelineFixture.date(hour: 10, minute: 0, calendar: calendar)

        // endAt nil AND dueAt nil → end falls back to start (zero length).
        let noEnd = TaskItem(title: "No end", startAt: start)
        // endAt == startAt → explicit zero length.
        let zeroEnd = TaskItem(title: "Zero end", startAt: start, endAt: start)

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [noEnd, zeroEnd],
            events: [],
            calendar: calendar
        ).blocks

        #expect(blocks.count == 2)
        for block in blocks {
            // 10:00 → 10.0; synthetic floor is start + 0.25h (15 min).
            #expect(block.a == 10.0)
            #expect(block.b >= block.a + 0.25)
            #expect(block.b > block.a)  // never degenerate / inverted
        }
    }

    @Test("Inverted endAt < startAt yields a non-inverted synthetic rect")
    func invertedEndSynthetic() throws {
        let calendar = TimelineFixture.utcCalendar
        let start = TimelineFixture.date(hour: 15, minute: 0, calendar: calendar)
        let earlierEnd = TimelineFixture.date(hour: 13, minute: 0, calendar: calendar)
        let task = TaskItem(title: "Inverted", startAt: start, endAt: earlierEnd)

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [task],
            events: [],
            calendar: calendar
        ).blocks

        let block = try #require(blocks.first)
        #expect(block.a == 15.0)
        // b = max(13.0, 15.0 + 0.25) = 15.25 → never < a.
        #expect(block.b > block.a)
        #expect(block.b == 15.25)
    }

    @Test("Early-morning and late-evening blocks render at true time (never dropped)")
    func outOfBusinessHoursBlocksPresent() throws {
        let calendar = TimelineFixture.utcCalendar
        // 07:00–08:00 (before old 9 floor); 21:00–22:00 (after old 20 ceiling).
        let early = TaskItem(
            title: "Early",
            startAt: TimelineFixture.date(hour: 7, minute: 0, calendar: calendar),
            endAt: TimelineFixture.date(hour: 8, minute: 0, calendar: calendar)
        )
        let late = TaskItem(
            title: "Late",
            startAt: TimelineFixture.date(hour: 21, minute: 0, calendar: calendar),
            endAt: TimelineFixture.date(hour: 22, minute: 0, calendar: calendar)
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [early, late],
            events: [],
            calendar: calendar
        ).blocks

        #expect(blocks.map(\.title) == ["Early", "Late"])
        #expect(blocks.map(\.a) == [7.0, 21.0])
        #expect(blocks.map(\.b) == [8.0, 22.0])
    }

    @Test("Block spans are no longer clamped — true start/end are preserved")
    func spansPreservedUnclamped() throws {
        let calendar = TimelineFixture.utcCalendar
        // 08:00–10:00 and 19:00–21:00 used to clamp to the 9–20 window; now the
        // full-day axis keeps their true bounds.
        let spansStart = TaskItem(
            title: "Spans start",
            startAt: TimelineFixture.date(hour: 8, minute: 0, calendar: calendar),
            endAt: TimelineFixture.date(hour: 10, minute: 0, calendar: calendar)
        )
        let spansEnd = TaskItem(
            title: "Spans end",
            startAt: TimelineFixture.date(hour: 19, minute: 0, calendar: calendar),
            endAt: TimelineFixture.date(hour: 21, minute: 0, calendar: calendar)
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [spansStart, spansEnd],
            events: [],
            calendar: calendar
        ).blocks

        #expect(blocks.count == 2)
        let first = try #require(blocks.first)
        let last = try #require(blocks.last)
        #expect(first.a == 8.0)  // unclamped
        #expect(first.b == 10.0)
        #expect(last.a == 19.0)
        #expect(last.b == 21.0)  // unclamped
    }

    @Test("Empty input yields an empty result with no crash or NaN")
    func emptyInput() {
        let result = TodayDashboard.embeddedTimelineBlocks(
            tasks: [],
            events: [],
            calendar: TimelineFixture.utcCalendar
        )
        #expect(result.blocks.isEmpty)
        #expect(result.allDay.isEmpty)
    }

    @Test("Soft-deleted tasks are excluded from the timeline")
    func deletedTaskExcluded() throws {
        let calendar = TimelineFixture.utcCalendar
        let live = TaskItem(
            title: "Live",
            startAt: TimelineFixture.date(hour: 11, minute: 0, calendar: calendar)
        )
        let deleted = TaskItem(
            title: "Deleted",
            startAt: TimelineFixture.date(hour: 12, minute: 0, calendar: calendar)
        )
        deleted.deletedAt = TimelineFixture.date(hour: 9, minute: 0, calendar: calendar)

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [live, deleted],
            events: [],
            calendar: calendar
        ).blocks

        #expect(blocks.map(\.title) == ["Live"])
    }

    @Test("Tasks without startAt never contribute a block")
    func unscheduledTaskDropped() throws {
        let calendar = TimelineFixture.utcCalendar
        let unscheduled = TaskItem(
            title: "Unscheduled",
            dueAt: TimelineFixture.date(hour: 14, minute: 0, calendar: calendar)
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [unscheduled],
            events: [],
            calendar: calendar
        ).blocks

        #expect(blocks.isEmpty)
    }

    @Test("Multiple tasks and events are merged and sorted ascending by start")
    func multipleBlocksSorted() throws {
        let calendar = TimelineFixture.utcCalendar
        let t16 = TaskItem(
            title: "Task 16",
            startAt: TimelineFixture.date(hour: 16, minute: 0, calendar: calendar),
            endAt: TimelineFixture.date(hour: 16, minute: 30, calendar: calendar)
        )
        let t10 = TaskItem(
            title: "Task 10",
            startAt: TimelineFixture.date(hour: 10, minute: 0, calendar: calendar),
            endAt: TimelineFixture.date(hour: 11, minute: 0, calendar: calendar)
        )
        let event13 = CalendarEvent(
            id: "ev-13",
            title: "Event 13",
            start: TimelineFixture.date(hour: 13, minute: 0, calendar: calendar),
            end: TimelineFixture.date(hour: 14, minute: 0, calendar: calendar)
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [t16, t10],
            events: [event13],
            calendar: calendar
        ).blocks

        #expect(blocks.map(\.title) == ["Task 10", "Event 13", "Task 16"])
        #expect(blocks.map(\.a) == [10.0, 13.0, 16.0])
        #expect(blocks.first?.id == "task:\(t10.id.uuidString)")
        #expect(blocks.dropFirst().first?.id == "event:ev-13")
    }

    @Test("All-day event is routed to the all-day strip, not the hour axis")
    func allDayEventRoutedToStrip() throws {
        let calendar = TimelineFixture.utcCalendar
        let allDay = CalendarEvent(
            id: "all-day",
            title: "All day",
            start: TimelineFixture.date(hour: 0, minute: 0, calendar: calendar),
            end: TimelineFixture.date(hour: 23, minute: 59, calendar: calendar),
            isAllDay: true
        )

        let result = TodayDashboard.embeddedTimelineBlocks(
            tasks: [],
            events: [allDay],
            calendar: calendar
        )

        // Not a timed block …
        #expect(result.blocks.isEmpty)
        // … it lives in the all-day strip instead.
        #expect(result.allDay.map(\.title) == ["All day"])
        #expect(result.allDay.first?.id == "event:all-day")
    }

    @Test("A timed event starting at 00:00 still renders on the axis (not dropped)")
    func midnightTimedEventRendered() throws {
        let calendar = TimelineFixture.utcCalendar
        // A real timed event at 00:00–01:00 (isAllDay == false) must appear at
        // its true position — the old 9–20 window would have dropped it.
        let midnight = CalendarEvent(
            id: "midnight",
            title: "Midnight call",
            start: TimelineFixture.date(hour: 0, minute: 0, calendar: calendar),
            end: TimelineFixture.date(hour: 1, minute: 0, calendar: calendar)
        )

        let result = TodayDashboard.embeddedTimelineBlocks(
            tasks: [],
            events: [midnight],
            calendar: calendar
        )

        #expect(result.allDay.isEmpty)
        let block = try #require(result.blocks.first)
        #expect(block.a == 0.0)
        #expect(block.b == 1.0)
        #expect(block.title == "Midnight call")
    }

    // MARK: - Free-time gap math (embeddedFreeTimeLabel)

    @Test("Gap >= 30 minutes (and < 60) renders a minute-only label")
    func freeTimeMinutesOnly() {
        // now = 9.0, next block starts at 9.75 (45 min gap).
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b", a: 9.75, b: 10.0, title: "Block", time: "09:45",
                endTime: "10:00")
        ]
        let label = TodayDashboard.embeddedFreeTimeLabel(nowFrac: 9.0, blocks: blocks)
        #expect(label?.text == "free · 45m")
        // Midpoint of the [9.0, 9.75] gap.
        #expect(label?.midFrac == 9.375)
    }

    @Test("Gap >= 60 minutes renders an hour+minute label")
    func freeTimeHoursAndMinutes() {
        // now = 10.0, next block at 12.5 → 150 min = 2h 30m.
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b", a: 12.5, b: 13.0, title: "Block", time: "12:30",
                endTime: "13:00")
        ]
        let label = TodayDashboard.embeddedFreeTimeLabel(nowFrac: 10.0, blocks: blocks)
        #expect(label?.text == "free · 2h 30m")
    }

    @Test("Gap shorter than 30 minutes is suppressed")
    func freeTimeSuppressedUnder30() {
        // now = 9.0, next block at 9.4 → 24 min < 30 → nil.
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b", a: 9.4, b: 10.0, title: "Block", time: "09:24",
                endTime: "10:00")
        ]
        let label = TodayDashboard.embeddedFreeTimeLabel(nowFrac: 9.0, blocks: blocks)
        #expect(label == nil)
    }

    @Test("No block strictly after now yields no free-time label")
    func freeTimeNoUpcomingBlock() {
        // Only a block in the past relative to now → nil.
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b", a: 9.0, b: 9.5, title: "Past", time: "09:00",
                endTime: "09:30")
        ]
        let label = TodayDashboard.embeddedFreeTimeLabel(nowFrac: 11.0, blocks: blocks)
        #expect(label == nil)
    }

    @Test("now at the end of the day yields no free-time label")
    func freeTimeNowPastWindow() {
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b", a: 19.0, b: 19.5, title: "Block", time: "19:00",
                endTime: "19:30")
        ]
        // gapStart = max(24.0, 0.0) = 24.0, not < windowEnd 24.0 → nil.
        let label = TodayDashboard.embeddedFreeTimeLabel(nowFrac: 24.0, blocks: blocks)
        #expect(label == nil)
    }

    @Test("Free-time gap spans up to a late evening block on the full-day axis")
    func freeTimeGapToLateBlock() {
        // On the full-day (0–24) axis a 23:00 block is in-window; gapEnd is the
        // block start. now = 19.0 → gap [19.0, 23.0] = 4h → "free · 4h 0m".
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b", a: 23.0, b: 23.5, title: "Far", time: "23:00",
                endTime: "23:30")
        ]
        let label = TodayDashboard.embeddedFreeTimeLabel(nowFrac: 19.0, blocks: blocks)
        #expect(label?.text == "free · 4h 0m")
        #expect(label?.midFrac == 21.0)
    }

}

/// Accessibility-label coverage for `embeddedTimelineAccessibilityLabels`.
/// Split into its own suite to keep each type body within the lint ceiling;
/// shares `TimelineFixture`. `@MainActor` for the same actor-isolation reason
/// as `EmbeddedTimelineBlocksTests`.
@Suite("EmbeddedTimeline accessibility")
@MainActor
struct EmbeddedTimelineA11yTests {

    @Test("Empty blocks with now in window yields a single now element")
    func a11yLabelsNowOnlyNoBlocks() throws {
        let calendar = TimelineFixture.utcCalendar
        let now = TimelineFixture.date(hour: 11, minute: 30, calendar: calendar)

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: [],
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Now, 11:30"])
    }

    @Test("Early-morning now is in the full-day window and yields a now element")
    func a11yLabelsEarlyMorningNow() throws {
        let calendar = TimelineFixture.utcCalendar
        // 07:00 was outside the old 9–20 window; on the full-day axis it is in
        // window, so a now element is emitted.
        let now = TimelineFixture.date(hour: 7, minute: 0, calendar: calendar)

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: [],
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Now, 07:00"])
    }

    @Test("Block labels use title and real start–end times")
    func a11yBlockLabelFormat() throws {
        let calendar = TimelineFixture.utcCalendar
        // Block 10:00–11:00; now is at 00:00 (before the block) so the block
        // label follows the now element — assert the block label format.
        let now = TimelineFixture.date(hour: 0, minute: 0, calendar: calendar)
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "t1", a: 10.0, b: 11.0, title: "Team standup",
                time: "10:00", endTime: "11:00")
        ]

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: blocks,
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Now, 00:00", "Team standup, 10:00–11:00"])
    }

    @Test("Now is interleaved chronologically between blocks")
    func a11yNowInterleaved() throws {
        let calendar = TimelineFixture.utcCalendar
        // Two blocks around now (10:00–11:00, 13:00–14:00); now = 11:30.
        let now = TimelineFixture.date(hour: 11, minute: 30, calendar: calendar)
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b1", a: 10.0, b: 11.0, title: "Morning sync",
                time: "10:00", endTime: "11:00"),
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b2", a: 13.0, b: 14.0, title: "Lunch review",
                time: "13:00", endTime: "14:00"),
        ]

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: blocks,
            now: now,
            calendar: calendar
        )

        #expect(
            labels == [
                "Morning sync, 10:00–11:00",
                "Now, 11:30",
                "Lunch review, 13:00–14:00",
            ])
    }

    @Test("Now before all blocks appears first")
    func a11yNowBeforeAllBlocks() throws {
        let calendar = TimelineFixture.utcCalendar
        // now = 09:00, block starts at 10:00 → now first.
        let now = TimelineFixture.date(hour: 9, minute: 0, calendar: calendar)
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b1", a: 10.0, b: 11.0, title: "Call",
                time: "10:00", endTime: "11:00")
        ]

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: blocks,
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Now, 09:00", "Call, 10:00–11:00"])
    }

    @Test("Now after all blocks appears last")
    func a11yNowAfterAllBlocks() throws {
        let calendar = TimelineFixture.utcCalendar
        // now = 18:00, block ends at 11:00 → now appended at end.
        let now = TimelineFixture.date(hour: 18, minute: 0, calendar: calendar)
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b1", a: 10.0, b: 11.0, title: "Retrospective",
                time: "10:00", endTime: "11:00")
        ]

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: blocks,
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Retrospective, 10:00–11:00", "Now, 18:00"])
    }

    @Test("Now at midnight (00:00) is the day's start boundary and is included")
    func a11yNowAtDayStartBoundary() throws {
        let calendar = TimelineFixture.utcCalendar
        let now = TimelineFixture.date(hour: 0, minute: 0, calendar: calendar)

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: [],
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Now, 00:00"])
    }

    @Test("endTime in block label reflects the original end time")
    func a11yEndTimeFromOriginalEnd() throws {
        let calendar = TimelineFixture.utcCalendar
        // Block 19:00–21:00 renders at its true bounds on the full-day axis;
        // now = 23:00 (after the block) so the now element is appended.
        let now = TimelineFixture.date(hour: 23, minute: 0, calendar: calendar)
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b1", a: 19.0, b: 21.0, title: "Late event",
                time: "19:00", endTime: "21:00")
        ]

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: blocks,
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Late event, 19:00–21:00", "Now, 23:00"])
    }

}

/// Shared fixtures (ScheduleGroupingTests idiom): a fixed UTC gregorian
/// calendar + deterministic component-built dates, used by both suites.
enum TimelineFixture {
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    static func date(
        hour: Int,
        minute: Int,
        calendar: Calendar,
        day: Int = 12
    ) -> Date {
        guard
            let date = calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 5,
                    day: day,
                    hour: hour,
                    minute: minute,
                    second: 0,
                    nanosecond: 0
                )
            )
        else {
            preconditionFailure("Invalid embedded timeline fixture date")
        }
        return date
    }
}
