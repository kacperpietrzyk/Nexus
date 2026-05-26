import Foundation
import Testing

@testable import NexusCore

@Suite("WatchAgendaSelector")
struct WatchAgendaSelectorTests {
    private func makeTask(
        title: String,
        dueAt: Date?,
        startAt: Date? = nil,
        priority: TaskPriority = .none,
        status: TaskStatus = .open,
        lastCompletedAt: Date? = nil
    ) -> TaskItem {
        let task = TaskItem(
            title: title,
            dueAt: dueAt,
            startAt: startAt,
            priority: priority,
            status: status
        )
        task.lastCompletedAt = lastCompletedAt
        return task
    }

    @Test("Overdue first, then today by dueAt, capped at 5")
    func overdueFirstCappedAtFive() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay)!
        let later = startOfDay.addingTimeInterval(60 * 60 * 4)

        let overdue1 = makeTask(title: "old1", dueAt: yesterday)
        let overdue2 = makeTask(title: "old2", dueAt: yesterday.addingTimeInterval(60))
        let today1 = makeTask(title: "t1", dueAt: later)
        let today2 = makeTask(title: "t2", dueAt: later.addingTimeInterval(60))
        let today3 = makeTask(title: "t3", dueAt: later.addingTimeInterval(120))
        let today4 = makeTask(title: "t4", dueAt: later.addingTimeInterval(180))

        let result = WatchAgendaSelector.pick(
            overdue: [overdue1, overdue2],
            today: [today1, today2, today3, today4],
            now: now
        )

        #expect(result.agenda.count == 5)
        #expect(result.agenda.map(\.title) == ["old1", "old2", "t1", "t2", "t3"])
        #expect(result.recentlyDone.isEmpty)
    }

    @Test("Empty buckets return empty AgendaResult")
    func emptyBuckets() {
        let result = WatchAgendaSelector.pick(
            overdue: [],
            today: [],
            now: .now
        )
        #expect(result.agenda.isEmpty)
        #expect(result.recentlyDone.isEmpty)
    }

    @Test("Fewer than max entries returns all in order")
    func fewerThanCap() {
        let now = Date()
        let task1 = makeTask(title: "a", dueAt: now.addingTimeInterval(60))
        let task2 = makeTask(title: "b", dueAt: now.addingTimeInterval(120))

        let result = WatchAgendaSelector.pick(
            overdue: [],
            today: [task1, task2],
            now: now
        )

        #expect(result.agenda.map(\.title) == ["a", "b"])
    }

    @Test("Recently done sorted by lastCompletedAt DESC, capped at 3")
    func recentlyDoneSortedAndCapped() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let done1 = makeTask(
            title: "d1",
            dueAt: nil,
            status: .done,
            lastCompletedAt: now.addingTimeInterval(-3600)
        )
        let done2 = makeTask(
            title: "d2",
            dueAt: nil,
            status: .done,
            lastCompletedAt: now.addingTimeInterval(-600)
        )
        let done3 = makeTask(
            title: "d3",
            dueAt: nil,
            status: .done,
            lastCompletedAt: now.addingTimeInterval(-7200)
        )
        let done4 = makeTask(
            title: "d4",
            dueAt: nil,
            status: .done,
            lastCompletedAt: now.addingTimeInterval(-1800)
        )

        let result = WatchAgendaSelector.pick(
            overdue: [],
            today: [],
            recentlyDone: [done1, done2, done3, done4],
            now: now
        )

        #expect(result.recentlyDone.map(\.title) == ["d2", "d4", "d1"])
    }

    @Test("Recently done with nil lastCompletedAt is excluded")
    func recentlyDoneSkipsNilTimestamps() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let valid = makeTask(title: "v", dueAt: nil, status: .done, lastCompletedAt: now)
        let nilStamp = makeTask(title: "n", dueAt: nil, status: .done, lastCompletedAt: nil)

        let result = WatchAgendaSelector.pick(
            overdue: [],
            today: [],
            recentlyDone: [valid, nilStamp],
            now: now
        )

        #expect(result.recentlyDone.map(\.title) == ["v"])
    }

    @Test("Custom maxRecentlyDone honored")
    func customMaxRecentlyDone() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let done1 = makeTask(
            title: "d1",
            dueAt: nil,
            status: .done,
            lastCompletedAt: now.addingTimeInterval(-100)
        )
        let done2 = makeTask(
            title: "d2",
            dueAt: nil,
            status: .done,
            lastCompletedAt: now.addingTimeInterval(-200)
        )

        let result = WatchAgendaSelector.pick(
            overdue: [],
            today: [],
            recentlyDone: [done1, done2],
            now: now,
            maxRecentlyDone: 1
        )

        #expect(result.recentlyDone.map(\.title) == ["d1"])
    }
}
