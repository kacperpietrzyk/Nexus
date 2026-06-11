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

    @Test func repeatingAbsoluteRoundTripsThroughCodable() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let rule = ReminderRule.absolute(at: when, repeats: .daily)
        let data = try JSONEncoder().encode([rule])
        let decoded = try JSONDecoder().decode([ReminderRule].self, from: data)
        #expect(decoded == [rule])
    }

    @Test func legacyAbsolutePayloadDecodesWithNilRepeats() throws {
        // Pre-T4 wire shape: no "repeat" key. Date uses the default Codable
        // strategy (seconds since reference date).
        let json = #"[{"kind":"absolute","at":700000000.0}]"#
        let decoded = try JSONDecoder().decode([ReminderRule].self, from: Data(json.utf8))
        #expect(decoded == [.absolute(Date(timeIntervalSinceReferenceDate: 700_000_000))])
    }

    @Test func oneShotAbsoluteEncodesWithoutRepeatKey() throws {
        let data = try JSONEncoder().encode([ReminderRule.absolute(Date(timeIntervalSince1970: 1))])
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let object = try #require(array?.first)
        #expect(object["repeat"] == nil)
    }

    @Test func absoluteFactoryEqualsNilRepeatsCase() {
        let when = Date(timeIntervalSince1970: 5)
        #expect(ReminderRule.absolute(when) == .absolute(at: when, repeats: nil))
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
