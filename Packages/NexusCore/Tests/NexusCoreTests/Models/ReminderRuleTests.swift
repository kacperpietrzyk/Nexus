import Foundation
import Testing
@testable import NexusCore

@Suite struct ReminderRuleTests {
    @Test func relativeRoundTripsThroughCodable() throws {
        let rule = ReminderRule.relative(offset: -1800, anchor: .due)
        let data = try JSONEncoder().encode([rule])
        let decoded = try JSONDecoder().decode([ReminderRule].self, from: data)
        #expect(decoded == [rule])
    }

    @Test func absoluteRoundTripsThroughCodable() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let rule = ReminderRule.absolute(when)
        let data = try JSONEncoder().encode([rule])
        let decoded = try JSONDecoder().decode([ReminderRule].self, from: data)
        #expect(decoded == [rule])
    }

    @Test func taskRemindersAccessorReadsAndWritesData() {
        let task = TaskItem(title: "t")
        #expect(task.reminders.isEmpty)

        task.reminders = [.relative(offset: -3600, anchor: .deadline), .absolute(Date(timeIntervalSince1970: 1))]
        #expect(task.reminders.count == 2)
        #expect(task.remindersData != nil)

        task.reminders = []
        #expect(task.reminders.isEmpty)
        #expect(task.remindersData == nil)
    }
}
