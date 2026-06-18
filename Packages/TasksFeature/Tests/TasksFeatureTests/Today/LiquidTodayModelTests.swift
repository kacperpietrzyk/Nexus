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

    @Test("Within a priority group, overdue task precedes due-today task")
    @MainActor
    func priorityGroupingOverdueBeforeToday() {
        let overdueTask = TaskItem(title: "overdue medium", dueAt: .now.addingTimeInterval(-86_400), priority: .medium)
        let todayTask = TaskItem(title: "today medium", dueAt: .now, priority: .medium)

        let groups = LiquidTodayModel.priorityGroups(
            overdue: [overdueTask],
            today: [todayTask]
        )

        #expect(groups.count == 1)
        let mediumGroup = groups[0]
        #expect(mediumGroup.priority == .medium)
        #expect(mediumGroup.tasks.count == 2)
        #expect(mediumGroup.tasks[0].id == overdueTask.id)
        #expect(mediumGroup.tasks[1].id == todayTask.id)
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

    // MARK: - selectTodayProjects

    @Test("selectTodayProjects puts pinned first (pinnedAt desc), then non-pinned by updatedAt desc, capped")
    @MainActor
    func selectTodayProjectsPutsPinnedFirstThenRecent() {
        func t(_ offset: TimeInterval) -> Date { Date(timeIntervalSince1970: offset) }

        let pinnedOld = Project(name: "pinOld"); pinnedOld.isPinned = true; pinnedOld.pinnedAt = t(1)
        let pinnedNew = Project(name: "pinNew"); pinnedNew.isPinned = true; pinnedNew.pinnedAt = t(3)
        let recent = Project(name: "recent"); recent.updatedAt = t(9)
        let old = Project(name: "old"); old.updatedAt = t(2)
        let out = LiquidTodayModel.selectTodayProjects([old, recent, pinnedOld, pinnedNew], cap: 3)
        #expect(out.map(\.name) == ["pinNew", "pinOld", "recent"])
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

    // MARK: - Skip-redundant-reload gate (return-navigation, FIX 1)

    @MainActor
    private func makeGateContext() throws -> (ModelContext, Date) {
        let container = try ModelContainer(
            for: TaskItem.self, Link.self, Project.self, Note.self, ScheduledBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let task = TaskItem(title: "due today", dueAt: .now)
        context.insert(task)
        try context.save()
        return (context, .now)
    }

    @MainActor
    private func reloadGate(_ model: LiquidTodayModel, _ context: ModelContext, now: Date) async {
        await model.reload(
            modelContext: context,
            calendarProvider: MockCalendarEventProvider(status: .denied),
            calendarEventsEnabled: false,
            meetingIntelProvider: nil,
            briefProvider: nil,
            now: now
        )
    }

    @Test("Second reload with same day + clean dirty flag does NOT re-read the store")
    @MainActor
    func skipRedundantReload() async throws {
        let (context, now) = try makeGateContext()
        let model = LiquidTodayModel()

        await reloadGate(model, context, now: now)
        #expect(model.storeLoadCount == 1)
        let snapshotPriorities = model.priorityGroups

        // Return-navigation: same day, no change -> early return, no re-read.
        await reloadGate(model, context, now: now)
        #expect(model.storeLoadCount == 1)
        // Snapshot is preserved exactly.
        #expect(model.priorityGroups == snapshotPriorities)
    }

    @Test("markDirty forces the next reload to re-read the store")
    @MainActor
    func markDirtyForcesReload() async throws {
        let (context, now) = try makeGateContext()
        let model = LiquidTodayModel()

        await reloadGate(model, context, now: now)
        #expect(model.storeLoadCount == 1)

        model.markDirty()
        await reloadGate(model, context, now: now)
        #expect(model.storeLoadCount == 2)
    }

    @Test("Day rollover forces the next reload to re-read the store")
    @MainActor
    func dayRolloverForcesReload() async throws {
        let (context, now) = try makeGateContext()
        let model = LiquidTodayModel()

        await reloadGate(model, context, now: now)
        #expect(model.storeLoadCount == 1)

        // Cross midnight: a new day-start must force a recompute.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        await reloadGate(model, context, now: tomorrow)
        #expect(model.storeLoadCount == 2)
    }

    @Test("isLoaded is false before the first reload and true after a successful load")
    @MainActor
    func isLoadedFlipsAfterFirstLoad() async throws {
        let (context, now) = try makeGateContext()
        let model = LiquidTodayModel()

        // Cold start: no load has completed -> the card must suppress its placeholder.
        #expect(model.isLoaded == false)

        await reloadGate(model, context, now: now)
        #expect(model.isLoaded)

        // A gated return-navigation (early-return, no re-read) must NOT reset it.
        await reloadGate(model, context, now: now)
        #expect(model.storeLoadCount == 1)
        #expect(model.isLoaded)
    }

    @Test("Changing calendarEventsEnabled forces the next reload to re-read the store")
    @MainActor
    func calendarToggleForcesReload() async throws {
        let (context, now) = try makeGateContext()
        let model = LiquidTodayModel()

        await reloadGate(model, context, now: now)
        #expect(model.storeLoadCount == 1)

        // Same day, clean flag, but calendar toggle flips -> must recompute.
        await model.reload(
            modelContext: context,
            calendarProvider: MockCalendarEventProvider(status: .denied),
            calendarEventsEnabled: true,
            meetingIntelProvider: nil,
            briefProvider: nil,
            now: now
        )
        #expect(model.storeLoadCount == 2)
    }

    @Test("Gate preserves the exact snapshot the un-gated reload produced")
    @MainActor
    func gateSnapshotIsIdentical() async throws {
        let (context, now) = try makeGateContext()

        // Baseline: a fresh model that reloads once (the gate never trips on a
        // first load) captures the canonical snapshot.
        let baseline = LiquidTodayModel()
        await reloadGate(baseline, context, now: now)

        // A second model reloaded twice (second is gated) must match field-for-field.
        let gated = LiquidTodayModel()
        await reloadGate(gated, context, now: now)
        await reloadGate(gated, context, now: now)

        #expect(gated.priorityGroups == baseline.priorityGroups)
        #expect(gated.projects == baseline.projects)
        #expect(gated.agendaItems == baseline.agendaItems)
        #expect(gated.projectNamesByID == baseline.projectNamesByID)
        #expect(gated.storeLoadCount == 1)
    }

    // MARK: - Focus gap (Task 6: empty-calendar reframe)

    @Test("suggestedFocusGap returns nil when events array is empty")
    @MainActor
    func focusGapNilWhenNoEvents() {
        // A passthrough provider that always claims the whole window is free —
        // so a non-nil result can only come from the events-empty guard.
        let passthroughProvider: LiquidTodayFocusGapProvider = { _, window in [window] }
        let now = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0,
            of: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        let gap = LiquidTodayModel.suggestedFocusGap(events: [], provider: passthroughProvider, now: now)
        #expect(gap == nil)
    }

    @Test("suggestedFocusGap returns a non-nil gap when at least one event is present")
    @MainActor
    func focusGapPresentWhenEventsExist() {
        // A provider that always returns the whole remaining window as one gap.
        let realProvider: LiquidTodayFocusGapProvider = { _, window in [window] }
        let now = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0,
            of: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        let dayStart = Calendar.current.startOfDay(for: now)
        let eventStart = dayStart.addingTimeInterval(10 * 3600)
        let event = CalendarEvent(
            id: "e1",
            title: "Meeting",
            start: eventStart,
            end: eventStart.addingTimeInterval(3600)
        )
        let gap = LiquidTodayModel.suggestedFocusGap(events: [event], provider: realProvider, now: now)
        #expect(gap != nil)
    }

    // MARK: - Reference data

    @Test("Reference snapshot supplies dense Today data without persistence")
    @MainActor
    func referenceTodaySnapshotIsDense() {
        let snapshot = LiquidTodayReferenceData.snapshot(now: .now)
        #expect(snapshot.agendaItems.count >= 5)
        #expect(snapshot.priorityGroups.count >= 3)
        #expect(snapshot.projects.count >= 3)
        #expect(snapshot.meetingIntel?.actionItemCount ?? 0 >= 3)
        #expect(!snapshot.brief.isEmpty)
    }
}
