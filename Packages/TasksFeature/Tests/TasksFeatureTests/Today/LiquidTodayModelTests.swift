import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("LiquidTodayModel pure helpers")
struct LiquidTodayModelTests {

    // MARK: - Priority grouping

    @Test("Groups overdue + today tasks by priority, descending, dropping empty buckets")
    @MainActor
    func priorityGrouping() {
        let overdueHigh = TaskItem(title: "overdue high", dueAt: .now.addingTimeInterval(-86_400), priority: .high)
        let todayHigh = TaskItem(title: "today high", dueAt: .now, priority: .high)
        let todayLow = TaskItem(title: "today low", dueAt: .now, priority: .low)
        let todayNone = TaskItem(title: "today none", dueAt: .now)

        let groups = LiquidTodayModel.priorityGroups(
            overdue: [overdueHigh],
            today: [todayHigh, todayLow, todayNone]
        )

        #expect(groups.map(\.priority) == [.high, .low, TaskPriority.none])
        #expect(groups[0].tasks.map(\.title) == ["overdue high", "today high"])
        #expect(groups[1].tasks.map(\.title) == ["today low"])
        #expect(groups[2].tasks.map(\.title) == ["today none"])
    }

    @Test("Deduplicates a task present in both the overdue and today buckets")
    @MainActor
    func priorityGroupingDeduplicates() {
        let shared = TaskItem(title: "shared", dueAt: .now, priority: .medium)
        let groups = LiquidTodayModel.priorityGroups(overdue: [shared], today: [shared])
        #expect(groups.count == 1)
        #expect(groups[0].tasks.count == 1)
    }

    // MARK: - Agenda assembly

    @Test("Sorts timed events + accepted blocks by start; all-day floats to the top")
    @MainActor
    func agendaAssembly() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        let nine = dayStart.addingTimeInterval(9 * 3600)
        let eleven = dayStart.addingTimeInterval(11 * 3600)

        let timed = CalendarEvent(id: "e1", title: "Standup", start: eleven, end: eleven.addingTimeInterval(1800))
        let allDay = CalendarEvent(id: "e2", title: "Offsite", start: dayStart, end: dayStart.addingTimeInterval(86_400), isAllDay: true)
        let block = ScheduledBlock(
            taskID: UUID(),
            start: nine,
            end: nine.addingTimeInterval(3600),
            title: "Deep work",
            status: .accepted
        )

        let items = LiquidTodayModel.agendaItems(events: [timed, allDay], blocks: [block])

        #expect(items.map(\.title) == ["Offsite", "Deep work", "Standup"])
        #expect(items[1].kind == .focus)
        #expect(items[2].kind == .meeting)
    }

    // MARK: - Due metadata

    @Test("Due labels: today, overdue, future")
    @MainActor
    func dueLabels() {
        let now = Date.now
        let today = TaskItem(title: "a", dueAt: now)
        let overdue = TaskItem(title: "b", dueAt: now.addingTimeInterval(-2 * 86_400))
        let future = TaskItem(title: "c", dueAt: now.addingTimeInterval(5 * 86_400))
        let undated = TaskItem(title: "d")

        #expect(TopPrioritiesCard.dueLabel(for: today, now: now) == "Due today")
        #expect(TopPrioritiesCard.dueLabel(for: overdue, now: now)?.hasPrefix("Overdue · ") == true)
        #expect(TopPrioritiesCard.dueLabel(for: future, now: now)?.hasPrefix("Due ") == true)
        #expect(TopPrioritiesCard.dueLabel(for: undated, now: now) == nil)
    }

    // MARK: - Brief marker stripping

    @Test("Strips digest emphasis markers and Markdown heading runs")
    @MainActor
    func briefStripping() {
        let raw = "## Three things matter today\n[[accent]]Push the auth flow[[/accent]] and [[mono]]review[[/mono]]."
        let cleaned = LiquidTodayText.strippingMarkers(from: raw)
        #expect(cleaned == "Three things matter today\nPush the auth flow and review.")
    }

    // MARK: - Focus timer label

    @Test("Elapsed ring label uses tabular m:ss-style formatting")
    @MainActor
    func elapsedLabel() {
        let now = Date.now
        let task = TaskItem(title: "t", startAt: now.addingTimeInterval(-65 * 60))
        #expect(TodayInspector.elapsedText(for: task, now: now) == "1:05")
        let unstarted = TaskItem(title: "u")
        #expect(TodayInspector.elapsedText(for: unstarted, now: now) == "0:00")
    }
}
