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

    @Test func addAbsoluteAppendsAndDeduplicates() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        var rules: [ReminderRule] = []
        rules = RemindersReducer.add(.absolute(when), to: rules)
        #expect(rules == [.absolute(when)])
        // Identical rule should be deduped
        rules = RemindersReducer.add(.absolute(when), to: rules)
        #expect(rules.count == 1)
    }

    @Test @MainActor func describeAbsoluteReturnsFormattedNonEmptyString() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let label = RemindersEditor.describe(.absolute(when))
        #expect(!label.isEmpty)
    }
}
