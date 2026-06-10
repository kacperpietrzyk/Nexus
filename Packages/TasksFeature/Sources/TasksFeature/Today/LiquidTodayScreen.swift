import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Spec `docs/04_LAYOUT_SYSTEM.md` §Grid Rules / Today Dashboard:
/// "Today's Agenda — width ~380".
private let agendaCardWidth: CGFloat = 380
/// Reference proportions (`references/01_today_dashboard.png`): the agenda/
/// priorities row holds ~40% of the page height even when sparse, so empty
/// states stay calm cards rather than collapsing the grid.
private let topRowMinHeight: CGFloat = 340
/// Reference proportions: the three lower cards share one baseline height
/// (04_LAYOUT_SYSTEM.md §Visual Alignment "karty lower dashboard powinny mieć
/// zbliżoną wysokość").
private let bottomRowMinHeight: CGFloat = 240

/// The Liquid `Today / Command Center` main column (Task 5, spec
/// `docs/05_MODULE_TODAY.md`): serif page header, then Agenda + Top
/// Priorities on top and Projects / Notes / Meeting Intelligence as the
/// 3-column bottom row. The matching right inspector (`TodayInspector`) is
/// mounted separately through `LiquidAppShell`'s inspector slot; both read
/// the same shared `LiquidTodayModel`.
///
/// Cross-module content (meeting intel, daily brief) enters through injected
/// value providers composed in the app layer — TasksFeature imports neither
/// NexusMeetings nor NexusAgent.
public struct LiquidTodayScreen: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var taskRepository
    @Environment(\.calendarEventProvider) private var calendarProvider
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NexusPreferences.Keys.calendarEventsInTodayEnabled) private var calendarEventsEnabled = false

    private let model: LiquidTodayModel
    private let meetingIntelProvider: LiquidTodayMeetingIntelProvider?
    private let briefProvider: LiquidTodayBriefProvider?
    private let focusGapProvider: LiquidTodayFocusGapProvider?
    private let onNavigate: (TodayNavSelection) -> Void
    private let onOpenTask: (TaskItem) -> Void
    private let onOpenCapture: (CapturePane.Mode) -> Void

    @State private var cascadePrompt: CascadeCompletionPrompt?
    @State private var actionError: String?

    public init(
        model: LiquidTodayModel,
        meetingIntelProvider: LiquidTodayMeetingIntelProvider?,
        briefProvider: LiquidTodayBriefProvider?,
        focusGapProvider: LiquidTodayFocusGapProvider? = nil,
        onNavigate: @escaping (TodayNavSelection) -> Void,
        onOpenTask: @escaping (TaskItem) -> Void,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void
    ) {
        self.model = model
        self.meetingIntelProvider = meetingIntelProvider
        self.briefProvider = briefProvider
        self.focusGapProvider = focusGapProvider
        self.onNavigate = onNavigate
        self.onOpenTask = onOpenTask
        self.onOpenCapture = onOpenCapture
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                header

                if let error = actionError ?? model.loadError {
                    errorRow(error)
                }

                HStack(alignment: .top, spacing: DS.Space.m) {
                    TodayAgendaCard(
                        items: model.agendaItems,
                        now: .now,
                        onOpenCalendar: { onNavigate(.calendar) }
                    )
                    .frame(width: agendaCardWidth)
                    .frame(maxHeight: .infinity)

                    TopPrioritiesCard(
                        groups: model.priorityGroups,
                        now: .now,
                        projectName: { model.projectNamesByID[$0] },
                        onToggle: { toggleDone($0) },
                        onOpen: onOpenTask,
                        onAddTask: { onOpenCapture(.task) },
                        onViewAll: { onNavigate(.tasks) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                }
                .frame(minHeight: topRowMinHeight)
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: DS.Space.m) {
                    TodayProjectsCard(
                        projects: model.projects,
                        onOpenProjects: { onNavigate(.projects) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                    TodayNotesCard(
                        notes: model.notes,
                        onOpenNotes: { onNavigate(.notes) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                    MeetingIntelCard(
                        intel: model.meetingIntel,
                        onOpenMeetings: { onNavigate(.meetings) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                }
                .frame(minHeight: bottomRowMinHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await reload() }
        .task(id: calendarEventsEnabled) { await reload() }
        .reloadOnStoreChange { _Concurrency.Task { await reload() } }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            _Concurrency.Task { await reload() }
        }
        .cascadeCompletionConfirmation($cascadePrompt) { prompt in
            confirmCascade(prompt)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text("Today")
                .font(DS.FontToken.displayLarge)
                .foregroundStyle(DS.ColorToken.textPrimary)
            // Real formatted date only — the reference's weather chip has no
            // backing service and is intentionally omitted (no fake data).
            Text(Self.dateFormatter.string(from: .now))
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.statusWarning)
            Text(message)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .lineLimit(2)
        }
        .padding(DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.card, radius: DS.Radius.m)
    }

    // MARK: - Data + actions

    private func reload() async {
        await model.reload(
            modelContext: modelContext,
            calendarProvider: calendarProvider,
            calendarEventsEnabled: calendarEventsEnabled,
            meetingIntelProvider: meetingIntelProvider,
            briefProvider: briefProvider,
            focusGapProvider: focusGapProvider
        )
    }

    /// Mirrors the embedded-Today checkbox semantics (`embeddedToggleDone`):
    /// real repository complete/reopen, the strict-completion throw raises the
    /// shared cascade confirmation, any other failure surfaces inline.
    private func toggleDone(_ task: TaskItem) {
        guard let taskRepository else { return }
        do {
            if task.status == .done {
                try taskRepository.reopen(task)
            } else {
                try TaskCompletionAction.complete(task, repository: taskRepository)
            }
            actionError = nil
            // Refresh the buckets immediately (mirrors the store-change hook;
            // don't leave the row stale until the autosave notification lands).
            _Concurrency.Task { await reload() }
        } catch let error as TaskItemRepositoryError {
            if case .parentHasOpenSubtasks(let parentID, let openCount) = error, parentID == task.id {
                cascadePrompt = CascadeCompletionPrompt(task: task, openCount: openCount)
            } else {
                actionError = String(describing: error)
            }
        } catch {
            actionError = String(describing: error)
        }
    }

    private func confirmCascade(_ prompt: CascadeCompletionPrompt) {
        guard let taskRepository else { return }
        do {
            try TaskCompletionAction.cascadeComplete(prompt.task, repository: taskRepository)
            actionError = nil
            // Same immediate refresh as toggleDone's success path.
            _Concurrency.Task { await reload() }
        } catch {
            actionError = String(describing: error)
        }
    }
}
