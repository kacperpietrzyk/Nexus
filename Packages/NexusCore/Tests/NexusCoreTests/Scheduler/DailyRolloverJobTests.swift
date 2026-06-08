import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("DailyRolloverJob")
struct DailyRolloverJobTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test("nextWorkday skips the weekend")
    func nextWorkdaySkipsWeekend() {
        let cal = calendar
        // 2026-06-05 10:00 UTC is a Friday.
        let friday = Date(timeIntervalSince1970: 1_780_653_600)
        let next = DailyRolloverJob.nextWorkday(after: friday, calendar: cal)
        // Friday + 1 = Saturday → skip → Sunday → skip → Monday 2026-06-08.
        let components = cal.dateComponents([.weekday], from: next)
        #expect(components.weekday == 2)  // Monday
    }

    @MainActor
    @Test("rollover moves overdue open tasks to the next workday and keeps future tasks")
    func rollsOverdue() async throws {
        let schema = Schema([TaskItem.self, ScheduledBlock.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let cal = calendar

        // now = 2026-06-05 10:00 UTC (Friday); next workday = Monday 2026-06-08.
        let now = Date(timeIntervalSince1970: 1_780_653_600)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let nextWeek = cal.date(byAdding: .day, value: 7, to: now)!

        let overdue = TaskItem(title: "overdue", dueAt: yesterday)
        let future = TaskItem(title: "future", dueAt: nextWeek)
        context.insert(overdue)
        context.insert(future)
        try context.save()

        let overdueID = overdue.id
        let futureID = future.id
        try await DailyRolloverJob.rollover(in: container, now: now, calendar: cal)

        // Re-fetch in a fresh context (rollover mutates its own context; the
        // store is the source of truth after its save).
        let verifyContext = ModelContext(container)
        let rolledOverdue = try #require(
            try verifyContext.fetch(
                FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == overdueID })
            ).first
        )
        let unchangedFuture = try #require(
            try verifyContext.fetch(
                FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == futureID })
            ).first
        )

        // Overdue rolled to a future workday; future untouched.
        #expect((rolledOverdue.dueAt ?? .distantPast) > now)
        #expect(unchangedFuture.dueAt == nextWeek)
    }

    @MainActor
    @Test("rollover leaves a task still due later today untouched (only genuinely overdue rolls, S1)")
    func leavesDueLaterTodayUntouched() async throws {
        let schema = Schema([TaskItem.self, ScheduledBlock.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let cal = calendar

        // now = 2026-06-05 10:00 UTC; a task due today at 17:00 is still ahead.
        let now = Date(timeIntervalSince1970: 1_780_653_600)
        let dueToday = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
        let task = TaskItem(title: "later today", dueAt: dueToday)
        context.insert(task)
        try context.save()
        let id = task.id

        try await DailyRolloverJob.rollover(in: container, now: now, calendar: cal)

        let verify = ModelContext(container)
        let after = try #require(
            try verify.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
        )
        #expect(after.dueAt == dueToday)
    }
}
