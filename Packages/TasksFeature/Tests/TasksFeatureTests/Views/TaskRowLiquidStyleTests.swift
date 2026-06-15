import Foundation
import NexusCore
import NexusUI
import Testing

@testable import TasksFeature

// MARK: - Liquid row presentation helpers

@Suite("TaskRowLiquidStyle — tag accents")
struct TaskRowLiquidStyleTagTests {

    @Test("tag accent index is deterministic across calls")
    func tagAccentDeterministic() {
        for tag in ["personal", "cybersecurity", "attack", "ünïcødé", ""] {
            let first = TaskRowLiquidStyle.tagAccentIndex(for: tag)
            let second = TaskRowLiquidStyle.tagAccentIndex(for: tag)
            #expect(first == second, "index must be stable for \(tag)")
        }
    }

    @Test("tag accent index stays within the palette")
    func tagAccentBounds() {
        for tag in ["a", "bb", "ccc", "personal", "infra", "🦊"] {
            let index = TaskRowLiquidStyle.tagAccentIndex(for: tag)
            #expect(index >= 0 && index < TaskRowLiquidStyle.tagAccents.count)
        }
    }

    @Test("different tags can take different accents (not all collapsed)")
    func tagAccentSpread() {
        let tags = ["personal", "cybersecurity", "attack", "email", "work", "infra", "design"]
        let indices = Set(tags.map { TaskRowLiquidStyle.tagAccentIndex(for: $0) })
        #expect(indices.count > 1, "a realistic tag set must not collapse onto one accent")
    }
}

@Suite("TaskRowLiquidStyle — visible tag capping")
struct TaskRowLiquidStyleCapTests {

    @Test("under the cap, all tags are visible with zero overflow")
    func underCap() {
        let split = TaskRowLiquidStyle.visibleTags(["one", "two"])
        #expect(split.visible == ["one", "two"])
        #expect(split.overflow == 0)
    }

    @Test("over the cap, exactly cap tags show and the overflow count is real")
    func overCap() {
        let split = TaskRowLiquidStyle.visibleTags(["a", "b", "c", "d", "e"])
        #expect(split.visible == ["a", "b"])
        #expect(split.overflow == 3)
    }

    @Test("empty tags produce no pills and no overflow")
    func empty() {
        let split = TaskRowLiquidStyle.visibleTags([])
        #expect(split.visible.isEmpty)
        #expect(split.overflow == 0)
    }
}

@Suite("TaskRowLiquidStyle — due metadata")
struct TaskRowLiquidStyleDueTests {

    @Test("no date renders nothing")
    func noDate() {
        #expect(TaskRowLiquidStyle.dueMetadata(for: .noDate) == nil)
    }

    @Test("overdue renders the single red token text")
    func overdue() {
        let due = TaskRowLiquidStyle.dueMetadata(for: .overdue(daysLate: 3))
        #expect(due?.text == "3d late")
        #expect(due?.role == .overdue)
    }

    @Test("today with and without a time")
    func today() {
        #expect(TaskRowLiquidStyle.dueMetadata(for: .today(timeOfDay: nil))?.text == "Today")
        let timed = TaskRowLiquidStyle.dueMetadata(for: .today(timeOfDay: "14:00"))
        #expect(timed?.text == "Today 14:00")
        #expect(timed?.role == .today)
    }

    @Test("tomorrow and future read as quiet upcoming metadata")
    func upcoming() {
        let tomorrow = TaskRowLiquidStyle.dueMetadata(for: .tomorrow(timeOfDay: nil))
        #expect(tomorrow?.text == "Tomorrow")
        #expect(tomorrow?.role == .upcoming)

        let future = TaskRowLiquidStyle.dueMetadata(for: .future(date: "Jun 14", timeOfDay: "09:30"))
        #expect(future?.text == "Jun 14 09:30")
        #expect(future?.role == .upcoming)
    }
}

@Suite("TaskRowLiquidStyle — priority labels")
struct TaskRowLiquidStylePriorityTests {

    @Test("priority labels are short; no-priority omits the pill")
    func labels() {
        #expect(TaskRowLiquidStyle.priorityLabel(for: .high) == "High")
        #expect(TaskRowLiquidStyle.priorityLabel(for: .medium) == "Med")
        #expect(TaskRowLiquidStyle.priorityLabel(for: .low) == "Low")
        #expect(TaskRowLiquidStyle.priorityLabel(for: TaskPriority.none) == nil)
    }
}

// MARK: - Liquid checkbox state mapping

@Suite("LiquidTaskCheckboxState — status mapping")
struct LiquidTaskCheckboxStateTests {

    @Test("open maps to .open")
    func openMapsToOpen() {
        #expect(liquidCheckboxState(for: .open) == .open)
    }

    @Test("done maps to .done")
    func doneMapsToDone() {
        #expect(liquidCheckboxState(for: .done) == .done)
    }

    @Test("snoozed maps to .snoozed (dashed ring, truthful state)")
    func snoozedMapsToSnoozed() {
        #expect(liquidCheckboxState(for: .snoozed) == .snoozed)
    }

    @Test("all TaskStatus cases are covered (exhaustive switch guard)")
    func allCasesCovered() {
        for status in TaskStatus.allCases {
            let state = liquidCheckboxState(for: status)
            switch status {
            case .open:
                #expect(state == .open)
            case .done:
                #expect(state == .done)
            case .snoozed:
                #expect(state == .snoozed)
            }
        }
    }
}
