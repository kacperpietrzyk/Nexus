import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("TodayDashboard skeleton")
struct TodayDashboardTests {
    @Test("Builds default dashboard")
    @MainActor
    func buildDefaultDashboard() {
        _ = TodayDashboard()
    }

    @Test("Nav selection is hashable and sendable")
    func navSelectionContract() {
        let selections: Set<TodayNavSelection> = [
            .today, .inbox, .meetings, .tasks, .agent, .stats, .settings,
        ]
        #expect(selections.count == 7)
        #expect(selections.contains(.meetings))
        #expect(selections.contains(.agent))
        #expect(selections.contains(.stats))
    }

    @Test("Stats selection routes to productivity dashboard content")
    func statsSelectionRoutesToProductivityDashboard() {
        #expect(TodayDashboardContentRoute.route(for: .stats) == .productivity)
    }

    @Test("Agent selection is mounted in the app shell slot, not this router")
    func agentSelectionRoutesDefensivelyToToday() {
        // Agent is a full nav-rail shell destination mounted directly in the
        // app-level shell content slot; `TodayDashboard`'s internal content
        // router is never reached on that path. The defensive map keeps the
        // enum + content switch unchanged — lock it so a future hand cannot
        // re-route `.agent` here without a failing test.
        #expect(TodayDashboardContentRoute.route(for: .agent) == .today)
    }

    @Test("Ask action routes to the Agent shell destination")
    func askActionRoutesToAgent() {
        #expect(TodayDashboard.selectionAfterOpeningAsk() == .agent)
    }

    @Test("Ask action is visible only when host can route to Agent")
    func askActionVisibilityRequiresAgentRoute() {
        #expect(TodayDashboard.canOpenAgent(selectionProvided: true, callbackProvided: false))
        #expect(TodayDashboard.canOpenAgent(selectionProvided: false, callbackProvided: true))
        #expect(!TodayDashboard.canOpenAgent(selectionProvided: false, callbackProvided: false))
    }

    @Test("Inspector is suppressed while the Agent destination is active")
    func inspectorSuppressedUnderAgentSelection() {
        // The §1 "inspector ⊥ Agent" hard invariant: a selected task must
        // never present the task-detail inspector while the Agent shell
        // destination owns the content slot. Lock all three corners so a
        // future hand cannot regress the predicate.
        let task = TaskItem(title: "Selected")
        #expect(InspectorVisibility.shouldShowInspector(selectedTask: task, selection: .agent) == false)
        #expect(InspectorVisibility.shouldShowInspector(selectedTask: task, selection: .today) == true)
        #expect(InspectorVisibility.shouldShowInspector(selectedTask: nil, selection: .today) == false)
    }

    @Test("Meetings selection routes to Meetings content")
    func meetingsSelectionRoutesToMeetingsContent() {
        #expect(TodayDashboardContentRoute.route(for: .meetings) == .meetings)
    }

    @Test("Embedded day-timeline rail yields to routes that own a right pane")
    func embeddedTimelineRailVisibilityPerRoute() {
        // Audit B3 — "globalny ale dopracowany": the DZIEŃ rail is the
        // single global right rail on routes with no right column of their
        // own, but Inbox (InboxReaderPane) and Meetings (meeting detail)
        // already own a right pane, so mounting the 320pt rail there double-
        // railed. Linear redesign: `.tasks` now joins the false group too —
        // the DAY timeline is always empty on Tasks and crushed the list, so
        // the redesign frees the column (capped reading measure applied at
        // the `.tasks` route case instead). Lock every corner.
        #expect(TodayDashboardContentRoute.today.showsEmbeddedTimelineRail == true)
        #expect(TodayDashboardContentRoute.tasks.showsEmbeddedTimelineRail == false)
        #expect(TodayDashboardContentRoute.productivity.showsEmbeddedTimelineRail == true)
        #expect(TodayDashboardContentRoute.settings.showsEmbeddedTimelineRail == true)
        #expect(TodayDashboardContentRoute.inbox.showsEmbeddedTimelineRail == false)
        #expect(TodayDashboardContentRoute.meetings.showsEmbeddedTimelineRail == false)
    }

    @Test("Keeps task selection callback for transitional Today and Tasks content")
    @MainActor
    func taskSelectionCallbackContract() {
        let dashboard = TodayDashboard(onOpenTask: { _ in })
        #expect(dashboard.onOpenTask != nil)
    }

    @Test("Capture callback carries task and voice modes")
    @MainActor
    func captureModeCallbackContract() {
        var captured: [CapturePane.Mode] = []
        let dashboard = TodayDashboard(onOpenCapture: { captured.append($0) })

        dashboard.onOpenCapture(.task)
        dashboard.onOpenCapture(.voiceMemo)

        #expect(captured == [.task, .voiceMemo])
    }

    // MARK: - A10: embeddedTodayIsEmpty pure-static predicate

    @Test("Empty-state gate: all buckets empty, no pin, no error → true")
    @MainActor
    func embeddedIsEmptyWhenAllBucketsEmptyNoError() {
        #expect(
            TodayDashboard.embeddedTodayIsEmpty(
                todayTasks: [],
                awaiting: [],
                laterTasks: [],
                featuredNowTask: nil,
                error: nil
            ) == true
        )
    }

    @Test("Empty-state gate: load failure (error set) with zeroed buckets → false (no false achievement)")
    @MainActor
    func embeddedIsNotEmptyWhenLoadFailed() {
        // This is the regression the pure seam was extracted to lock:
        // a data-load failure zeros all buckets AND sets embeddedError.
        // Without the `error == nil` guard the zeroed buckets would satisfy
        // the gate and falsely show "All clear" on a failure.
        #expect(
            TodayDashboard.embeddedTodayIsEmpty(
                todayTasks: [],
                awaiting: [],
                laterTasks: [],
                featuredNowTask: nil,
                error: "SwiftData fetch failed"
            ) == false
        )
    }

    @Test("Empty-state gate: today bucket non-empty → false")
    @MainActor
    func embeddedIsNotEmptyWhenTodayBucketHasTasks() {
        let task = TaskItem(title: "Today task")
        #expect(
            TodayDashboard.embeddedTodayIsEmpty(
                todayTasks: [task],
                awaiting: [],
                laterTasks: [],
                featuredNowTask: nil,
                error: nil
            ) == false
        )
    }

    @Test("Empty-state gate: awaiting bucket non-empty → false")
    @MainActor
    func embeddedIsNotEmptyWhenAwaitingBucketHasEntries() {
        let task = TaskItem(title: "Awaiting task")
        let entry = AwaitingEntry(task: task, blockedCount: 1)
        #expect(
            TodayDashboard.embeddedTodayIsEmpty(
                todayTasks: [],
                awaiting: [entry],
                laterTasks: [],
                featuredNowTask: nil,
                error: nil
            ) == false
        )
    }

    @Test("Empty-state gate: later bucket non-empty → false")
    @MainActor
    func embeddedIsNotEmptyWhenLaterBucketHasTasks() {
        let task = TaskItem(title: "Later task")
        #expect(
            TodayDashboard.embeddedTodayIsEmpty(
                todayTasks: [],
                awaiting: [],
                laterTasks: [task],
                featuredNowTask: nil,
                error: nil
            ) == false
        )
    }

    @Test("Empty-state gate: pinned NowCard task (featuredNowTask non-nil) with empty buckets → false")
    @MainActor
    func embeddedIsNotEmptyWhenPinnedTaskPresent() {
        let pinned = TaskItem(title: "Pinned focus")
        #expect(
            TodayDashboard.embeddedTodayIsEmpty(
                todayTasks: [],
                awaiting: [],
                laterTasks: [],
                featuredNowTask: pinned,
                error: nil
            ) == false
        )
    }

    // MARK: - Schedule task loading

    @Test("Loads today's tasks for the schedule timeline")
    @MainActor
    func scheduleTaskLoading() throws {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 9)))
        let today = TaskItem(title: "Timed today", dueAt: now, startAt: now)
        let tomorrow = TaskItem(title: "Tomorrow", dueAt: now.addingTimeInterval(86_400))
        context.insert(today)
        context.insert(tomorrow)
        try context.save()

        let tasks = try TodayDashboard.scheduleTasks(now: now, modelContext: context)

        #expect(tasks.map { $0.title } == ["Timed today"])
        let schedule = ScheduleGrouping.group(tasks: tasks, events: [], now: now)
        #expect(schedule.slots.count == 1)
        #expect(schedule.unscheduled.isEmpty)
    }
}
