import Foundation
import NexusCore
import SwiftData
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

    @Test("Strips disobedient single-bracket markers and Markdown bold runs")
    @MainActor
    func briefStrippingModelDrift() {
        let raw = "**Three things matter today - [accent]push the auth flow[/accent], review Sam's PR.**"
        let cleaned = LiquidTodayText.strippingMarkers(from: raw)
        #expect(cleaned == "Three things matter today - push the auth flow, review Sam's PR.")
    }

    @Test("Normalizes Markdown bullet lines to typographic bullets")
    @MainActor
    func briefStrippingBullets() {
        let raw = "Przegląd\n* Główny problem: instalacja\n- Drugi punkt"
        let cleaned = LiquidTodayText.strippingMarkers(from: raw)
        #expect(cleaned == "Przegląd\n• Główny problem: instalacja\n• Drugi punkt")
    }

    // MARK: - Brief regeneration decision

    @Test("Brief regenerates on changed input or empty brief; skips on identical input with content")
    @MainActor
    func briefRegenerationDecision() {
        let now = Date.now
        let input = LiquidTodayBriefInput(overdue: 1, today: 2, noDate: 3, awaiting: 0, firstTitles: ["a"], now: now)
        let sameInput = LiquidTodayBriefInput(overdue: 1, today: 2, noDate: 3, awaiting: 0, firstTitles: ["a"], now: now)
        let changedInput = LiquidTodayBriefInput(overdue: 2, today: 2, noDate: 3, awaiting: 0, firstTitles: ["a"], now: now)

        // Identical input + held brief -> skip.
        #expect(!LiquidTodayModel.shouldRegenerateBrief(lastInput: input, newInput: sameInput, currentBrief: "held"))
        // Changed counts -> regenerate.
        #expect(LiquidTodayModel.shouldRegenerateBrief(lastInput: input, newInput: changedInput, currentBrief: "held"))
        // Identical input but no brief held yet -> regenerate.
        #expect(LiquidTodayModel.shouldRegenerateBrief(lastInput: input, newInput: sameInput, currentBrief: ""))
        // First load (no prior input) -> regenerate.
        #expect(LiquidTodayModel.shouldRegenerateBrief(lastInput: nil, newInput: input, currentBrief: ""))
    }

    // MARK: - Project progress

    @Test("Project progress orders by updatedAt desc and counts done/total per project")
    @MainActor
    func projectProgressOrdering() throws {
        let container = try ModelContainer(
            for: Project.self, TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let older = Project(name: "Older", status: .active)
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = Project(name: "Newer", status: .active)
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(older)
        context.insert(newer)

        let doneTask = TaskItem(title: "done")
        doneTask.statusRaw = TaskStatus.done.rawValue
        doneTask.projectID = newer.id
        let openTask = TaskItem(title: "open")
        openTask.projectID = newer.id
        context.insert(doneTask)
        context.insert(openTask)

        let progress = try LiquidTodayModel.projectProgress(
            activeProjects: [older, newer],
            modelContext: context
        )

        #expect(progress.map(\.project.name) == ["Newer", "Older"])
        #expect(progress[0].doneCount == 1)
        #expect(progress[0].totalCount == 2)
        #expect(progress[0].fraction == 0.5)
        #expect(progress[1].totalCount == 0)
        #expect(progress[1].fraction == 0)
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
