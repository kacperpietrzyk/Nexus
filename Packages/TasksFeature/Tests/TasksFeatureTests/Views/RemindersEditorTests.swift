import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite struct RemindersEditorTests {
    @Test func addRelativeChipAppendsRule() {
        var rules: [ReminderRule] = []
        rules = RemindersReducer.add(.relative(offset: -1800, anchor: .due), to: rules)
        #expect(rules == [.relative(offset: -1800, anchor: .due)])
    }

    @Test func removeAtIndexDropsRule() {
        let rules: [ReminderRule] = [
            .absolute(Date(timeIntervalSince1970: 1)),
            .relative(offset: -60, anchor: .due),
        ]
        let result = RemindersReducer.remove(at: 0, from: rules)
        #expect(result == [.relative(offset: -60, anchor: .due)])
    }

    @Test func addDeduplicatesIdenticalRule() {
        let existing: [ReminderRule] = [.relative(offset: -1800, anchor: .due)]
        let result = RemindersReducer.add(.relative(offset: -1800, anchor: .due), to: existing)
        #expect(result.count == 1)
    }
}
