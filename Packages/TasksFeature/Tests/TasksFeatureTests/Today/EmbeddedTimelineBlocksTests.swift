import Foundation
import NexusCore
import Testing

@testable import TasksFeature

/// Coverage for the MP-2 embedded-Today DayTimeline anchor transform
/// (`TodayDashboard.embeddedTimelineBlocks` + `embeddedFreeTimeLabel`),
/// folded in from the slice-4 review so the pure geometry is locked before
/// MP-2.2 freezes the pattern. Mirrors the `ScheduleGroupingTests` idiom:
/// fixed UTC gregorian calendar, deterministic component-built dates,
/// Swift Testing `@Test`/`#expect`.
///
/// `@MainActor` on the suite: `embeddedTimelineBlocks` /
/// `embeddedFreeTimeLabel` are statics on `TodayDashboard`, a SwiftUI
/// `View` (`@MainActor`-isolated under Swift 6 strict concurrency).
/// Calling them from a `nonisolated` test context is an actor-isolation
/// violation that traps the test runner at runtime — the same idiom
/// `TodayDashboardTests` uses for its `TodayDashboard.scheduleTasks(...)`
/// test (per-test `@MainActor`), hoisted to the suite here since every
/// case touches a `TodayDashboard` static.
@Suite("EmbeddedTimelineBlocks MP-2")
@MainActor
struct EmbeddedTimelineBlocksTests {

    // MARK: - clampedBlock geometry (via embeddedTimelineBlocks)

    @Test("nil/zero endAt yields a synthetic >=15-minute span, never degenerate")
    func syntheticSpanForMissingOrZeroEnd() throws {
        let calendar = utcCalendar
        let start = try #require(date(hour: 10, minute: 0, calendar: calendar))

        // endAt nil AND dueAt nil → end falls back to start (zero length).
        let noEnd = TaskItem(title: "No end", startAt: start)
        // endAt == startAt → explicit zero length.
        let zeroEnd = TaskItem(title: "Zero end", startAt: start, endAt: start)

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [noEnd, zeroEnd],
            events: [],
            calendar: calendar
        )

        #expect(blocks.count == 2)
        for block in blocks {
            // 10:00 → 10.0; synthetic floor is start + 0.25h (15 min).
            #expect(block.a == 10.0)
            #expect(block.b >= block.a + 0.25)
            #expect(block.b > block.a)  // never degenerate / inverted
        }
    }

    @Test("Inverted endAt < startAt is clamped to a non-inverted rect")
    func invertedEndClamped() throws {
        let calendar = utcCalendar
        let start = try #require(date(hour: 15, minute: 0, calendar: calendar))
        let earlierEnd = try #require(date(hour: 13, minute: 0, calendar: calendar))
        let task = TaskItem(title: "Inverted", startAt: start, endAt: earlierEnd)

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [task],
            events: [],
            calendar: calendar
        )

        let block = try #require(blocks.first)
        #expect(block.a == 15.0)
        // rawB = max(13.0, 15.0 + 0.25) = 15.25 → never < a.
        #expect(block.b > block.a)
        #expect(block.b == 15.25)
    }

    @Test("Block fully outside the 9-20 window is dropped, not degenerate")
    func outsideWindowDropped() throws {
        let calendar = utcCalendar
        // 07:00–08:00 fully before 9; 21:00–22:00 fully after 20.
        let early = TaskItem(
            title: "Early",
            startAt: try #require(date(hour: 7, minute: 0, calendar: calendar)),
            endAt: try #require(date(hour: 8, minute: 0, calendar: calendar))
        )
        let late = TaskItem(
            title: "Late",
            startAt: try #require(date(hour: 21, minute: 0, calendar: calendar)),
            endAt: try #require(date(hour: 22, minute: 0, calendar: calendar))
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [early, late],
            events: [],
            calendar: calendar
        )

        #expect(blocks.isEmpty)
    }

    @Test("Partial overlap is clamped to the window edges")
    func partialOverlapClamped() throws {
        let calendar = utcCalendar
        // 08:00–10:00 → clamp start up to 9.0; 19:00–21:00 → clamp end to 20.0.
        let spansStart = TaskItem(
            title: "Spans start",
            startAt: try #require(date(hour: 8, minute: 0, calendar: calendar)),
            endAt: try #require(date(hour: 10, minute: 0, calendar: calendar))
        )
        let spansEnd = TaskItem(
            title: "Spans end",
            startAt: try #require(date(hour: 19, minute: 0, calendar: calendar)),
            endAt: try #require(date(hour: 21, minute: 0, calendar: calendar))
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [spansStart, spansEnd],
            events: [],
            calendar: calendar
        )

        #expect(blocks.count == 2)
        let first = try #require(blocks.first)
        let last = try #require(blocks.last)
        #expect(first.a == 9.0)  // clamped up from 8.0
        #expect(first.b == 10.0)
        #expect(last.a == 19.0)
        #expect(last.b == 20.0)  // clamped down from 21.0
    }

    @Test("Empty input yields an empty result with no crash or NaN")
    func emptyInput() {
        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [],
            events: [],
            calendar: utcCalendar
        )
        #expect(blocks.isEmpty)
    }

    @Test("Soft-deleted tasks are excluded from the timeline")
    func deletedTaskExcluded() throws {
        let calendar = utcCalendar
        let live = TaskItem(
            title: "Live",
            startAt: try #require(date(hour: 11, minute: 0, calendar: calendar))
        )
        let deleted = TaskItem(
            title: "Deleted",
            startAt: try #require(date(hour: 12, minute: 0, calendar: calendar))
        )
        deleted.deletedAt = try #require(date(hour: 9, minute: 0, calendar: calendar))

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [live, deleted],
            events: [],
            calendar: calendar
        )

        #expect(blocks.map(\.title) == ["Live"])
    }

    @Test("Tasks without startAt never contribute a block")
    func unscheduledTaskDropped() throws {
        let calendar = utcCalendar
        let unscheduled = TaskItem(
            title: "Unscheduled",
            dueAt: try #require(date(hour: 14, minute: 0, calendar: calendar))
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [unscheduled],
            events: [],
            calendar: calendar
        )

        #expect(blocks.isEmpty)
    }

    @Test("Multiple tasks and events are merged and sorted ascending by start")
    func multipleBlocksSorted() throws {
        let calendar = utcCalendar
        let t16 = TaskItem(
            title: "Task 16",
            startAt: try #require(date(hour: 16, minute: 0, calendar: calendar)),
            endAt: try #require(date(hour: 16, minute: 30, calendar: calendar))
        )
        let t10 = TaskItem(
            title: "Task 10",
            startAt: try #require(date(hour: 10, minute: 0, calendar: calendar)),
            endAt: try #require(date(hour: 11, minute: 0, calendar: calendar))
        )
        let event13 = CalendarEvent(
            id: "ev-13",
            title: "Event 13",
            start: try #require(date(hour: 13, minute: 0, calendar: calendar)),
            end: try #require(date(hour: 14, minute: 0, calendar: calendar))
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [t16, t10],
            events: [event13],
            calendar: calendar
        )

        #expect(blocks.map(\.title) == ["Task 10", "Event 13", "Task 16"])
        #expect(blocks.map(\.a) == [10.0, 13.0, 16.0])
        #expect(blocks.first?.id == "task:\(t10.id.uuidString)")
        #expect(blocks.dropFirst().first?.id == "event:ev-13")
    }

    @Test("All-day event at 00:00 collapses outside 9-20 and is dropped")
    func allDayEventDropped() throws {
        let calendar = utcCalendar
        // Wall-clock 00:00 → fractionalHour 0.0, below the 9-20 window.
        let allDay = CalendarEvent(
            id: "all-day",
            title: "All day",
            start: try #require(date(hour: 0, minute: 0, calendar: calendar)),
            end: try #require(date(hour: 0, minute: 0, calendar: calendar))
        )

        let blocks = TodayDashboard.embeddedTimelineBlocks(
            tasks: [],
            events: [allDay],
            calendar: calendar
        )

        #expect(blocks.isEmpty)
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
        #expect(label?.text == "wolne · 45m")
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
        #expect(label?.text == "wolne · 2h 30m")
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

    @Test("now past the window end yields no free-time label")
    func freeTimeNowPastWindow() {
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b", a: 19.0, b: 19.5, title: "Block", time: "19:00",
                endTime: "19:30")
        ]
        // gapStart = max(21.0, 9.0) = 21.0, not < windowEnd 20.0 → nil.
        let label = TodayDashboard.embeddedFreeTimeLabel(nowFrac: 21.0, blocks: blocks)
        #expect(label == nil)
    }

    @Test("Free-time gap end is clamped to the window so a far block is bounded")
    func freeTimeGapClampedToWindow() {
        // Next block at 23.0 is outside the window; gapEnd clamps to 20.0.
        // now = 19.0 → gap [19.0, 20.0] = 60 min = "wolne · 1h 0m".
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b", a: 23.0, b: 23.5, title: "Far", time: "23:00",
                endTime: "23:30")
        ]
        let label = TodayDashboard.embeddedFreeTimeLabel(nowFrac: 19.0, blocks: blocks)
        #expect(label?.text == "wolne · 1h 0m")
        #expect(label?.midFrac == 19.5)
    }

    // MARK: - Accessibility labels (embeddedTimelineAccessibilityLabels)

    @Test("Empty blocks with now in window yields a single now element")
    func a11yLabelsNowOnlyNoBlocks() throws {
        let calendar = utcCalendar
        let now = try #require(date(hour: 11, minute: 30, calendar: calendar))

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: [],
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Now, 11:30"])
    }

    @Test("Empty blocks with now outside window yields empty result")
    func a11yLabelsNowOutsideWindowNoBlocks() throws {
        let calendar = utcCalendar
        // 07:00 is before the 9-20 window.
        let now = try #require(date(hour: 7, minute: 0, calendar: calendar))

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: [],
            now: now,
            calendar: calendar
        )

        #expect(labels.isEmpty)
    }

    @Test("Block labels use title and real start–end times")
    func a11yBlockLabelFormat() throws {
        let calendar = utcCalendar
        // Block 10:00–11:00; now outside window so only block label appears.
        let now = try #require(date(hour: 22, minute: 0, calendar: calendar))
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

        #expect(labels == ["Team standup, 10:00–11:00"])
    }

    @Test("Now is interleaved chronologically between blocks")
    func a11yNowInterleaved() throws {
        let calendar = utcCalendar
        // Two blocks around now (10:00–11:00, 13:00–14:00); now = 11:30.
        let now = try #require(date(hour: 11, minute: 30, calendar: calendar))
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
        let calendar = utcCalendar
        // now = 09:00, block starts at 10:00 → now first.
        let now = try #require(date(hour: 9, minute: 0, calendar: calendar))
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
        let calendar = utcCalendar
        // now = 18:00, block ends at 11:00 → now appended at end.
        let now = try #require(date(hour: 18, minute: 0, calendar: calendar))
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

    @Test("Now exactly at window boundary (20:00) is included")
    func a11yNowAtWindowBoundary() throws {
        let calendar = utcCalendar
        let now = try #require(date(hour: 20, minute: 0, calendar: calendar))

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: [],
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Now, 20:00"])
    }

    @Test("endTime in block label reflects original (un-clamped) end time")
    func a11yEndTimeIsUnclamped() throws {
        let calendar = utcCalendar
        // Block runs 19:00–21:00 but window clamps b to 20.0.
        // endTime should be "21:00" (original), not "20:00" (clamped b).
        let now = try #require(date(hour: 7, minute: 0, calendar: calendar))
        let blocks = [
            TodayDashboard.EmbeddedTimelineBlock(
                id: "b1", a: 19.0, b: 20.0, title: "Late event",
                time: "19:00", endTime: "21:00")
        ]

        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
            blocks: blocks,
            now: now,
            calendar: calendar
        )

        #expect(labels == ["Late event, 19:00–21:00"])
    }

    // MARK: - Fixtures (ScheduleGroupingTests idiom)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(
        hour: Int,
        minute: Int,
        calendar: Calendar,
        day: Int = 12
    ) -> Date? {
        calendar.date(
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
    }
}
