import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@MainActor
struct TaskGroupingTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .iso8601); c.timeZone = .current; return c
    }
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test("Group by priority orders High→Med→Low→None and omits empty")
    func byPriority() {
        let now = at("2026-06-19T12:00:00Z")
        let high = TaskItem(title: "h", priority: .high)
        let low = TaskItem(title: "l", priority: .low)
        let none = TaskItem(title: "n", priority: .none)
        let sections = taskGroupSections([low, none, high], by: .priority, projectsByID: [:], now: now, calendar: cal)
        #expect(sections.map(\.key) == ["High", "Low", "None"])  // Med empty → omitted
    }

    @Test("Group by date buckets overdue/today/tomorrow/later/no-date in order")
    func byDate() {
        let now = at("2026-06-19T12:00:00Z")
        let overdue = TaskItem(title: "o", dueAt: at("2026-06-17T09:00:00Z"))
        let today = TaskItem(title: "t", dueAt: at("2026-06-19T09:00:00Z"))
        let noDate = TaskItem(title: "x")
        let sections = taskGroupSections([noDate, today, overdue], by: .date, projectsByID: [:], now: now, calendar: cal)
        #expect(sections.map(\.key) == ["Overdue", "Today", "No date"])
    }

    @Test("Group by project puts named projects first, No project last")
    func byProject() {
        let now = at("2026-06-19T12:00:00Z")
        let proj = Project(name: "CyberLab")
        let inProj = TaskItem(title: "a"); inProj.projectID = proj.id
        let orphan = TaskItem(title: "b")
        let sections = taskGroupSections([orphan, inProj], by: .project, projectsByID: [proj.id: proj], now: now, calendar: cal)
        #expect(sections.map(\.key) == ["CyberLab", "No project"])
    }

    @Test("Group by none returns one anonymous group with all items in input order")
    func byNone() {
        let now = at("2026-06-19T12:00:00Z")
        let a = TaskItem(title: "a"); let b = TaskItem(title: "b")
        let sections = taskGroupSections([a, b], by: .none, projectsByID: [:], now: now, calendar: cal)
        #expect(sections.count == 1)
        #expect(sections[0].items.count == 2)
    }

    @Test("Group by date covers tomorrow / this week / later boundaries")
    func byDateBoundaries() {
        let now = at("2026-06-19T12:00:00Z")
        let tomorrow = TaskItem(title: "tm", dueAt: at("2026-06-20T09:00:00Z"))
        let thisWeek = TaskItem(title: "tw", dueAt: at("2026-06-23T09:00:00Z"))  // 4 days out
        let later = TaskItem(title: "lt", dueAt: at("2026-06-30T09:00:00Z"))  // 11 days out
        let sections = taskGroupSections([later, thisWeek, tomorrow], by: .date, projectsByID: [:], now: now, calendar: cal)
        #expect(sections.map(\.key) == ["Tomorrow", "This week", "Later"])
    }

    @Test("Group by none uses empty key and preserves input order")
    func byNoneContract() {
        let now = at("2026-06-19T12:00:00Z")
        let a = TaskItem(title: "a")
        let b = TaskItem(title: "b")
        let sections = taskGroupSections([a, b], by: .none, projectsByID: [:], now: now, calendar: cal)
        #expect(sections.count == 1)
        #expect(sections[0].key.isEmpty)
        #expect(sections[0].items.map(\.title) == ["a", "b"])
    }
}
