import Foundation
import Testing

@testable import TasksFeature

@Suite("TaskDetailRecurrenceChoice anchor handling")
struct TaskDetailRecurrenceChoiceTests {
    @Test("curated rules map to their base choice regardless of the ANCHOR token")
    func anchoredCuratedRules() {
        #expect(TaskDetailRecurrenceChoice.from(rrule: "FREQ=DAILY;ANCHOR=COMPLETION") == .daily)
        #expect(TaskDetailRecurrenceChoice.from(rrule: "FREQ=WEEKLY;ANCHOR=COMPLETION") == .weekly)
        #expect(TaskDetailRecurrenceChoice.from(rrule: "FREQ=MONTHLY;ANCHOR=COMPLETION") == .monthly)
    }

    @Test("unanchored mapping is unchanged")
    func unanchored() {
        #expect(TaskDetailRecurrenceChoice.from(rrule: "FREQ=DAILY") == .daily)
        #expect(TaskDetailRecurrenceChoice.from(rrule: nil) == TaskDetailRecurrenceChoice.none)
    }

    @Test("a non-curated anchored rule is still custom")
    func customAnchored() {
        #expect(
            TaskDetailRecurrenceChoice.from(rrule: "FREQ=WEEKLY;BYDAY=MO;ANCHOR=COMPLETION")
                == .custom)
    }
}
