import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("ScheduleGrouping v4")
struct ScheduleGroupingTests {
    @Test("Groups by exact minute and sorts ascending")
    func groupingOrder() throws {
        let calendar = testCalendar
        let nine = try #require(date(hour: 9, minute: 0, calendar: calendar))
        let nineThirty = try #require(
            date(hour: 9, minute: 30, calendar: calendar)
        )
        let ten = try #require(date(hour: 10, minute: 0, calendar: calendar))

        let t930 = TaskItem(title: "Later task", startAt: nineThirty)
        let t9 = TaskItem(title: "First task", startAt: nine)
        let event = CalendarEvent(
            id: "event-10",
            title: "Planning",
            start: ten,
            end: ten.addingTimeInterval(45 * 60)
        )

        let result = ScheduleGrouping.group(tasks: [t930, t9], events: [event], now: nine, calendar: calendar)

        #expect(result.slots.count == 3)
        #expect(result.slots.map(\.0) == [nine, nineThirty, ten])
        #expect(result.unscheduled.isEmpty)
    }

    @Test("Splits tasks without startAt into unscheduled")
    func unscheduledSplit() {
        let scheduledStart = Date(timeIntervalSince1970: 1_778_579_400)
        let scheduled = TaskItem(title: "Timed", startAt: scheduledStart)
        let unscheduled = TaskItem(title: "Inbox", dueAt: scheduledStart)

        let result = ScheduleGrouping.group(tasks: [unscheduled, scheduled], events: [], now: scheduledStart)

        #expect(result.slots.count == 1)
        #expect(result.unscheduled.map(\.title) == ["Inbox"])
    }

    @Test("Normalizes seconds and nanoseconds to the minute")
    func minuteNormalization() throws {
        let calendar = testCalendar
        let startWithSeconds = try #require(
            date(hour: 9, minute: 15, calendar: calendar, subsecond: (42, 123_000_000))
        )
        let minuteStart = try #require(
            date(hour: 9, minute: 15, calendar: calendar)
        )
        let task = TaskItem(title: "Normalized", startAt: startWithSeconds)

        let result = ScheduleGrouping.group(tasks: [task], events: [], now: minuteStart, calendar: calendar)

        #expect(result.slots.map(\.0) == [minuteStart])
    }

    @Test("isCurrent uses inclusive start and exclusive end")
    func currentEdgeBehavior() throws {
        let calendar = testCalendar
        let start = try #require(date(hour: 11, minute: 0, calendar: calendar))
        let end = start.addingTimeInterval(30 * 60)
        let task = TaskItem(title: "Focus", startAt: start, endAt: end)
        let item = ScheduleItem.task(task)

        #expect(ScheduleGrouping.isCurrent(item: item, now: start))
        #expect(ScheduleGrouping.isCurrent(item: item, now: end.addingTimeInterval(-1)))
        #expect(!ScheduleGrouping.isCurrent(item: item, now: end))
        #expect(ScheduleGrouping.isCurrent(item: .task(TaskItem(title: "Due", dueAt: end, startAt: start)), now: start))
        #expect(!ScheduleGrouping.isCurrent(item: .task(TaskItem(title: "Open", startAt: start)), now: start))
        #expect(!ScheduleGrouping.isCurrent(item: .task(TaskItem(title: "No start", endAt: end)), now: start))
    }

    @Test("Constrains grouped items to the current day and clamps overnight starts")
    func currentDayConstraint() throws {
        let calendar = testCalendar
        let now = try #require(date(hour: 9, minute: 0, calendar: calendar))
        let dayStart = calendar.startOfDay(for: now)
        let previousNight = try #require(date(hour: 23, minute: 30, calendar: calendar, day: 11))
        let tomorrow = try #require(date(hour: 9, minute: 0, calendar: calendar, day: 13))
        let overnightTask = TaskItem(
            title: "Overnight",
            dueAt: dayStart.addingTimeInterval(60 * 60),
            startAt: previousNight
        )
        let tomorrowTask = TaskItem(title: "Tomorrow", dueAt: tomorrow, startAt: tomorrow)
        let event = CalendarEvent(
            id: "overnight-event",
            title: "Deploy",
            start: previousNight,
            end: dayStart.addingTimeInterval(30 * 60)
        )

        let result = ScheduleGrouping.group(
            tasks: [overnightTask, tomorrowTask],
            events: [event],
            now: now,
            calendar: calendar
        )

        #expect(result.slots.count == 1)
        #expect(result.slots.first?.0 == dayStart)
        #expect(result.slots.first?.1.count == 2)
    }

    @Test("Scheduled blocks render as block items, excluding soft-deleted ones")
    func blocksGrouped() throws {
        let calendar = testCalendar
        let ten = try #require(date(hour: 10, minute: 0, calendar: calendar))
        let eleven = try #require(date(hour: 11, minute: 0, calendar: calendar))

        let live = ScheduledBlock(
            taskID: UUID(),
            start: ten,
            end: ten.addingTimeInterval(3600),
            title: "Deep work",
            status: .proposed
        )
        let deleted = ScheduledBlock(
            taskID: UUID(),
            start: eleven,
            end: eleven.addingTimeInterval(3600),
            title: "Gone",
            status: .proposed
        )
        deleted.deletedAt = ten

        let result = ScheduleGrouping.group(
            tasks: [],
            events: [],
            blocks: [live, deleted],
            now: ten,
            calendar: calendar
        )

        let allItems = result.slots.flatMap(\.1)
        let blockItems = allItems.filter { if case .block = $0 { return true } else { return false } }
        #expect(blockItems.count == 1)
        #expect(blockItems.first?.id == "block:\(live.id.uuidString)")
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(
        hour: Int,
        minute: Int,
        calendar: Calendar,
        day: Int = 12,
        subsecond: (second: Int, nanosecond: Int) = (0, 0)
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
                second: subsecond.second,
                nanosecond: subsecond.nanosecond
            )
        )
    }
}
