import NexusAgent
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Spec `docs/04_LAYOUT_SYSTEM.md` §Grid Rules / Today Dashboard:
/// "Today's Agenda — width ~380".
private let agendaCardWidth: CGFloat = 380

#if os(iOS)
/// Measures the Today pane width so the iPad layout can place the inspector as a
/// side column in landscape (wide) and stack it below in portrait (narrow) —
/// `horizontalSizeClass` is `.regular` in both iPad orientations, so it can't
/// distinguish them; the actual width can.
private struct TodayPaneWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
/// At/above this pane width the inspector sits as a side column; below it stacks
/// under the card grid (iPad portrait, narrow split).
private let inspectorSideMinWidth: CGFloat = 820
#endif

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
    // Proactive-insight stores (see `TodayDashboard+Insights`). Nil when the
    // host hasn't wired the insight coordinator (previews, test beds) — the
    // banner then no-ops. Read here so the shared Today screen surfaces
    // insights on macOS AND iOS; the legacy `TodayDashboard` path that owned
    // these reads no longer renders.
    @Environment(\.pendingInsightStore) private var pendingInsightStore
    @Environment(\.insightProposalCoordinator) private var insightProposalCoordinator
    @Environment(\.insightCooldownStore) private var insightCooldownStore
    @AppStorage(NexusPreferences.Keys.calendarEventsInTodayEnabled) private var calendarEventsEnabled = false

    private let model: LiquidTodayModel
    private let meetingIntelProvider: LiquidTodayMeetingIntelProvider?
    private let briefProvider: LiquidTodayBriefProvider?
    private let focusGapProvider: LiquidTodayFocusGapProvider?
    /// Meeting pin toggle seam: the app layer (which imports NexusMeetings)
    /// fetches the meeting by id and calls `MeetingRepository.setPinned`.
    /// `nil` = no toggle, the star renders read-only (reference/preview mode).
    private let onToggleMeetingPin: ((UUID) -> Void)?
    // On macOS the title+date moved into the window toolbar band, so the host
    // hides the in-content header (false). iOS/iPadOS has no toolbar band and
    // keeps the inline header (the default).
    private let showsInlineHeader: Bool
    private let onNavigate: (TodayNavSelection) -> Void
    private let onOpenTask: (TaskItem) -> Void
    private let onOpenCapture: (CapturePane.Mode) -> Void

    @State private var cascadePrompt: CascadeCompletionPrompt?
    @State private var actionError: String?

    #if os(iOS)
    // iOS reflows the macOS grid by size class and mounts the inspector inline
    // (there is no `LiquidAppShell` inspector slot on iOS). The capture draft
    // lives here because the iOS Today screen owns its own inspector.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var iosCaptureText = ""
    @State private var paneWidth: CGFloat = 0
    #endif

    public init(
        model: LiquidTodayModel,
        meetingIntelProvider: LiquidTodayMeetingIntelProvider?,
        briefProvider: LiquidTodayBriefProvider?,
        focusGapProvider: LiquidTodayFocusGapProvider? = nil,
        onToggleMeetingPin: ((UUID) -> Void)? = nil,
        showsInlineHeader: Bool = true,
        onNavigate: @escaping (TodayNavSelection) -> Void,
        onOpenTask: @escaping (TaskItem) -> Void,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void
    ) {
        self.model = model
        self.meetingIntelProvider = meetingIntelProvider
        self.briefProvider = briefProvider
        self.focusGapProvider = focusGapProvider
        self.onToggleMeetingPin = onToggleMeetingPin
        self.showsInlineHeader = showsInlineHeader
        self.onNavigate = onNavigate
        self.onOpenTask = onOpenTask
        self.onOpenCapture = onOpenCapture
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            content
                .padding(DS.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            TodaySceneWash()
                .allowsHitTesting(false)
        }
        #if os(iOS)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: TodayPaneWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(TodayPaneWidthKey.self) { paneWidth = $0 }
        #endif
        .task { await reload() }
        .task(id: calendarEventsEnabled) { await reload() }
        .reloadOnStoreChange {
            // A real store change must bypass the skip-redundant-reload gate.
            model.markDirty()
            _Concurrency.Task { await reload() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Returning to the foreground may carry external (sync) changes the
            // store-change hook didn't observe in-process — force a fresh read.
            model.markDirty()
            _Concurrency.Task { await reload() }
        }
        .cascadeCompletionConfirmation($cascadePrompt) { prompt in
            confirmCascade(prompt)
        }
    }

    // MARK: - Layout (reflows per platform / size class)

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            compactContent
        } else {
            regularContent
        }
        #else
        gridContent
        #endif
    }

    /// macOS + iPad-regular: the two-row card grid. On macOS the inspector is
    /// mounted externally by `LiquidAppShell`; iPad mounts it alongside in
    /// `regularContent` (iOS has no shell inspector slot).
    private var gridContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            if showsInlineHeader {
                header
            }
            errorRowIfNeeded
            insightBanner()

            // Row height = the tallest card's intrinsic content (no magic
            // constant, no `.clipped()`): empty states stay compact instead of
            // stretching to a fixed 420 pt, and dense cards grow rather than
            // hard-truncating. `maxHeight: .infinity` makes the shorter card
            // match the taller one so the row stays baseline-aligned.
            HStack(alignment: .top, spacing: DS.Space.m) {
                agendaCell
                prioritiesCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: DS.Space.m) {
                projectsCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                meetingCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    #if os(iOS)
    /// The five main cards as an ADAPTIVE grid (not the macOS fixed 380 + 3-column
    /// row, which is wider than an iPad-11" pane and overflows). The grid picks the
    /// column count that fits the available width — 1 on iPhone, 2 on a narrow iPad
    /// pane, 3 on a wide one — so nothing truncates and there are no magic widths.
    private var iosCardGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240, maximum: .infinity), spacing: DS.Space.l, alignment: .top)],
            alignment: .leading,
            spacing: DS.Space.l
        ) {
            agendaCard
            prioritiesCard
            projectsCard
            meetingCard
        }
    }

    /// iPad regular: adaptive card grid + the inspector. Landscape (wide pane) =
    /// inspector as a right side column; portrait (narrow pane) = inspector stacked
    /// below the grid so the cards keep a comfortable two-up width instead of being
    /// squeezed to one column beside a fixed 300pt rail.
    @ViewBuilder
    private var regularContent: some View {
        if paneWidth >= inspectorSideMinWidth {
            HStack(alignment: .top, spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    header
                    errorRowIfNeeded
                    insightBanner()
                    iosCardGrid
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                inspectorColumn
                    .frame(width: 300)
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                header
                errorRowIfNeeded
                insightBanner()
                iosCardGrid
                inspectorColumn
            }
        }
    }

    /// iPhone compact: a single reflowed column (the adaptive grid collapses to one
    /// column at phone width), with the inspector cards stacked below.
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            header
            errorRowIfNeeded
            insightBanner()
            iosCardGrid
            inspectorColumn
        }
    }

    private var inspectorColumn: some View {
        TodayInspector(
            model: model,
            captureText: $iosCaptureText,
            onNavigate: onNavigate,
            onOpenCapture: onOpenCapture
        )
    }
    #endif

    // MARK: - Cards

    @ViewBuilder
    private var errorRowIfNeeded: some View {
        if let error = actionError ?? model.loadError {
            errorRow(error)
        }
    }

    /// Surfaces the top pending proactive insight as a ProposalConfirmCard-style
    /// banner, reusing the exact dashboard wiring (`insightCardModel` mapper +
    /// `InsightBannerRow`) so accept/dismiss behave identically to the legacy
    /// `TodayDashboard` path. No-ops cleanly when no store is wired or there is
    /// no pending insight.
    @ViewBuilder
    private func insightBanner() -> some View {
        if let store = pendingInsightStore, let entry = store.pending.first {
            let model = TodayDashboard.insightCardModel(
                entry: entry,
                pending: store,
                coordinator: insightProposalCoordinator,
                cooldown: insightCooldownStore
            )
            InsightBannerRow(model: model, extraCount: max(0, store.count - 1))
                .id(entry.id)
        }
    }

    /// macOS top-row agenda cell: a fixed-width column. When the agenda has
    /// events it fills the row height (matching Top Priorities); when empty it
    /// hugs its slim content so the row collapses and the second grid row
    /// (Projects + Meeting Intelligence) rises above the fold. `.fixedSize` on
    /// the empty branch defeats both the populated card's internal
    /// `maxHeight: .infinity` and the row's equal-height behavior.
    @ViewBuilder
    private var agendaCell: some View {
        if agendaIsEmpty {
            agendaCard
                .frame(width: agendaCardWidth)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            agendaCard
                .frame(width: agendaCardWidth)
                .frame(maxHeight: .infinity)
        }
    }

    private var agendaIsEmpty: Bool {
        if LiquidReferenceMode.isEnabled {
            return LiquidTodayReferenceData.snapshot(now: .now).agendaItems.isEmpty
        }
        return model.agendaItems.isEmpty
    }

    private var agendaCard: some View {
        let reference = LiquidReferenceMode.isEnabled ? LiquidTodayReferenceData.snapshot(now: .now) : nil
        return TodayAgendaCard(
            items: reference?.agendaItems ?? model.agendaItems,
            now: .now,
            onOpenCalendar: { onNavigate(.calendar) }
        )
    }

    private var prioritiesCard: some View {
        let reference = LiquidReferenceMode.isEnabled ? LiquidTodayReferenceData.snapshot(now: .now) : nil
        return TopPrioritiesCard(
            groups: reference?.priorityGroups ?? model.priorityGroups,
            // Reference/preview mode supplies data without a model load — treat it
            // as loaded so previews and reference snapshots are unaffected.
            isLoaded: reference != nil || model.isLoaded,
            now: .now,
            projectName: { projectID in
                reference?.projectNamesByID[projectID] ?? model.projectNamesByID[projectID]
            },
            onToggle: { task in
                guard !LiquidReferenceMode.isEnabled else { return }
                toggleDone(task)
            },
            onOpen: onOpenTask,
            onAddTask: { onOpenCapture(.task) },
            onViewAll: { onNavigate(.tasks) }
        )
    }

    private var projectsCard: some View {
        let reference = LiquidReferenceMode.isEnabled ? LiquidTodayReferenceData.snapshot(now: .now) : nil
        return TodayProjectsCard(
            projects: reference?.projects ?? model.projects,
            onOpenProjects: { onNavigate(.projects) },
            onTogglePin: LiquidReferenceMode.isEnabled
                ? nil
                : { [self] id in
                    guard let project = model.projects.first(where: { $0.id == id })?.project else { return }
                    try? ProjectRepository(context: modelContext).setPinned(project, !project.isPinned)
                    model.markDirty()
                    _Concurrency.Task { await reload() }
                }
        )
    }

    private var meetingCard: some View {
        let reference = LiquidReferenceMode.isEnabled ? LiquidTodayReferenceData.snapshot(now: .now) : nil
        return MeetingIntelCard(
            intel: reference?.meetingIntel ?? model.meetingIntel,
            onOpenMeetings: { onNavigate(.meetings) },
            onTogglePin: LiquidReferenceMode.isEnabled ? nil : onToggleMeetingPin
        )
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
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .liquidLightCard(cornerRadius: DS.Radius.m)
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
            // Mark dirty so this post-write reload bypasses the redundant-reload gate.
            model.markDirty()
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
            model.markDirty()
            _Concurrency.Task { await reload() }
        } catch {
            actionError = String(describing: error)
        }
    }
}

private struct TodaySceneWash: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.006), location: 0.0),
                    .init(color: DS.ColorToken.accentBlue.opacity(0.006), location: 0.18),
                    .init(color: .clear, location: 0.50),
                    .init(color: DS.ColorToken.accentAmber.opacity(0.004), location: 1.0),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.014),
                    DS.ColorToken.accentBlue.opacity(0.006),
                    .clear,
                ],
                center: UnitPoint(x: 0.92, y: 0.18),
                startRadius: 0,
                endRadius: 380
            )

            RadialGradient(
                colors: [
                    DS.ColorToken.accentAmber.opacity(0.005),
                    .clear,
                ],
                center: UnitPoint(x: 0.20, y: 0.96),
                startRadius: 0,
                endRadius: 420
            )
        }
    }
}
