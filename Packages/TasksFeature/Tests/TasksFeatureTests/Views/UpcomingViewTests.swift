import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("UpcomingView grouping")
struct UpcomingViewGroupingTests {

    @Test("groups tasks by due day and sorts within each day")
    func groupsByDueDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 9)))
        let tomorrowMorning = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 9))
        )
        let tomorrowAfternoon = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 16))
        )
        let dayAfter = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 12))
        )

        let tasks = [
            TaskItem(title: "Later tomorrow", dueAt: tomorrowAfternoon),
            TaskItem(title: "Day after", dueAt: dayAfter),
            TaskItem(title: "Early tomorrow", dueAt: tomorrowMorning),
        ]

        let buckets = UpcomingDayBucket.make(from: tasks, now: now, calendar: calendar)

        #expect(buckets.count == 2)
        #expect(buckets[0].title == "Tomorrow")
        #expect(buckets[0].tasks.map(\.title) == ["Early tomorrow", "Later tomorrow"])
        #expect(buckets[1].tasks.map(\.title) == ["Day after"])
    }

    @Test("ignores tasks without due dates")
    func ignoresUndatedTasks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let due = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))

        let buckets = UpcomingDayBucket.make(
            from: [
                TaskItem(title: "No date"),
                TaskItem(title: "Future", dueAt: due),
            ],
            now: now,
            calendar: calendar
        )

        #expect(buckets.count == 1)
        #expect(buckets[0].tasks.map(\.title) == ["Future"])
    }
}
