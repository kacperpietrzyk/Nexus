import Foundation
import NexusCore
import Testing

@testable import TasksFeature

// MARK: - priorityLabel mapping

@Suite("TaskListView.priorityLabel")
@MainActor
struct PriorityLabelTests {
    @Test("High priority maps to 'High'")
    func highLabel() {
        #expect(TaskListView.priorityLabel(.high) == "High")
    }

    @Test("Medium priority maps to 'Medium'")
    func mediumLabel() {
        #expect(TaskListView.priorityLabel(.medium) == "Medium")
    }

    @Test("Low priority maps to 'Low'")
    func lowLabel() {
        #expect(TaskListView.priorityLabel(.low) == "Low")
    }

    @Test("None priority maps to 'None'")
    func noneLabel() {
        #expect(TaskListView.priorityLabel(.none) == "None")
    }
}

// MARK: - Bulk snooze date math

@Suite("TaskListView.snoozeDate")
@MainActor
struct SnoozeDateTests {
    private static let referenceNow: Date = {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 18
        comps.hour = 14
        comps.minute = 30
        comps.second = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)!
    }()

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test("oneHour adds exactly 3600 seconds")
    func oneHourIsExact() {
        let result = TaskListView.snoozeDate(for: .oneHour, from: Self.referenceNow, calendar: Self.utcCalendar)
        #expect(result == Self.referenceNow.addingTimeInterval(3_600))
    }

    @Test("tomorrow returns start-of-next-day (midnight UTC)")
    func tomorrowIsMidnight() {
        let result = TaskListView.snoozeDate(for: .tomorrow, from: Self.referenceNow, calendar: Self.utcCalendar)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 19
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        let expected = Self.utcCalendar.date(from: comps)!
        #expect(result == expected)
    }

    @Test("tomorrow at 23:59 still rolls to next calendar day")
    func tomorrowLateNight() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 18
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        let late = Self.utcCalendar.date(from: comps)!
        let result = TaskListView.snoozeDate(for: .tomorrow, from: late, calendar: Self.utcCalendar)
        let resultDay = Self.utcCalendar.component(.day, from: result)
        #expect(resultDay == 19)
    }
}

// MARK: - Markdown metadata assembly

@Suite("TaskListView.markdownMetadata")
@MainActor
struct MarkdownMetadataTests {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    @Test("no priority, no due, no tags yields empty metadata")
    func emptyMetadata() {
        let item = TaskItem(title: "Plain task")
        let lines = TaskListView.markdownMetadata(for: item, dateFormatter: Self.formatter)
        #expect(lines.isEmpty)
    }

    @Test("priority none is omitted")
    func priorityNoneOmitted() {
        let item = TaskItem(title: "t", priority: .none)
        let lines = TaskListView.markdownMetadata(for: item, dateFormatter: Self.formatter)
        #expect(!lines.contains(where: { $0.hasPrefix("Priority:") }))
    }

    @Test("non-none priority appears in metadata")
    func priorityHighIncluded() {
        let item = TaskItem(title: "t", priority: .high)
        let lines = TaskListView.markdownMetadata(for: item, dateFormatter: Self.formatter)
        #expect(lines.contains("Priority: High"))
    }

    @Test("due date is formatted correctly")
    func dueDateFormatted() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 15
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let due = cal.date(from: comps)!
        let item = TaskItem(title: "t", dueAt: due)
        let lines = TaskListView.markdownMetadata(for: item, dateFormatter: Self.formatter)
        #expect(lines.contains("Due: Mar 15, 2026"))
    }

    @Test("tags are joined with ', '")
    func tagsJoined() {
        let item = TaskItem(title: "t", tags: ["swift", "ios"])
        let lines = TaskListView.markdownMetadata(for: item, dateFormatter: Self.formatter)
        #expect(lines.contains("Tags: swift, ios"))
    }

    @Test("all three metadata fields present together in order")
    func allFieldsPresent() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let due = cal.date(from: comps)!
        let item = TaskItem(title: "Full task", dueAt: due, priority: .medium, tags: ["a"])
        let lines = TaskListView.markdownMetadata(for: item, dateFormatter: Self.formatter)
        #expect(lines.count == 3)
        #expect(lines[0] == "Priority: Medium")
        #expect(lines[1] == "Due: Jan 1, 2026")
        #expect(lines[2] == "Tags: a")
    }
}
