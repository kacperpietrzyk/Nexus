import InboxShell
import NexusAI
import NexusAgent
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

public enum TodayNavSelection: Hashable, Sendable {
    case today
    case inbox
    case meetings
    case tasks
    case notes
    case calendar
    case people
    case agent
    case stats
    case settings
}

enum TodayDashboardContentRoute: Equatable {
    case today
    case inbox
    case meetings
    case tasks
    case productivity
    case settings

    static func route(for selection: TodayNavSelection) -> TodayDashboardContentRoute {
        switch selection {
        case .today:
            return .today
        case .inbox:
            return .inbox
        case .meetings:
            return .meetings
        case .tasks:
            return .tasks
        case .agent, .notes, .calendar, .people:
            // Agent/Notes/Calendar/People are full shell destinations mounted
            // directly in the app shell; this router is never reached on those paths.
            return .today
        case .stats:
            return .productivity
        case .settings:
            return .settings
        }
    }

    /// Whether the embedded (Nexus shell) Today day-timeline right rail
    /// (`embeddedTimelineRail`) is mounted on this route.
    ///
    /// Audit B3 — user decision "global but refined": the DAY rail
    /// stays the single global right rail on routes that have no right
    /// column of their own (`today`, `productivity`, `settings`),
    /// but `inbox` (owns `InboxReaderPane`, fixed 380) and `meetings` (owns
    /// the meeting-detail pane) already render their own right pane, so
    /// also mounting the 320pt rail there produced a competing double-rail.
    /// On those two routes the rail yields to the route's own pane.
    /// Linear redesign: `.tasks` joins the false group too — the Today-only
    /// DAY timeline is always empty here and crushed the list; the freed
    /// column is capped + hugged left at the `.tasks` route case instead.
    var showsEmbeddedTimelineRail: Bool {
        switch self {
        case .today, .productivity, .settings:
            return true
        case .tasks, .inbox, .meetings:
            return false
        }
    }
}

/// Pure decision for whether the task-detail inspector overlay may be
/// presented. The MP-2.2 §1 hard invariant is "inspector ⊥ Agent": the
/// task-detail inspector and the Agent surface must never co-occupy the
/// screen (the original render-bug was a triple-occupy dead void). Agent is
/// a full shell destination owning the whole content slot, so the inspector
/// is suppressed whenever the Agent destination is active even if a task is
/// still selected in state. Extracted as a pure static so the invariant is
/// locally obvious and unit-testable without driving SwiftUI — same §12
/// "extract a pure static predicate for regression testability" precedent as
/// `TodayDashboardContentRoute.route(for:)`. Lives in `TasksFeature` (not the
/// app target) because that is where `TodayNavSelection` is defined and where
/// the precedent predicate is tested; the `NexusMac` app target has no test
/// target, so an app-side static could not be reached from these tests.
public enum InspectorVisibility {
    public static func shouldShowInspector(
        selectedTask: TaskItem?,
        selection: TodayNavSelection
    ) -> Bool {
        selectedTask != nil && selection != .agent
    }
}

extension Notification.Name {
    /// Posted by `TodayDashboard` when the iOS user activates the in-rail Settings entry.
    /// The iOS app shell should switch to its Settings tab in response. Mac uses
    /// `@Environment(\.openSettings)` directly and does not post this.
    public static let nexusGoToSettings = Notification.Name("nexus.goToSettings")
}

public struct TodayDashboard: View {
    @Environment(\.modelContext) var modelContext
    // Internal (not `private`): read from the `+EmbeddedToday` extension file.
    @Environment(\.taskRepository) var taskRepository
    @Environment(\.aiRouter) private var aiRouter
    @Environment(\.agentBriefService) private var agentBriefService
    @Environment(\.calendarEventProvider) var calendarProvider
    @Environment(\.calendarEventWriter) var calendarWriter
    // The embedded-Today NowCard "Focus" pill routes to this existing
    // focus-mode entry (`FocusModeState.enter(taskID:)` — the same state
    // `ContentView.activeFocusState` reads and the ⌘. menu command drives
    // via `NexusMacApp.resolveFocusCandidate`). nil default = host app did
    // not enable focus mode; the pill no-ops then, per the documented
    // `FocusModeEnvironment` contract. No new behaviour invented.
    // Internal (not `private`): read from the `+EmbeddedToday` extension.
    @Environment(\.focusModeState) var focusModeState
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @AppStorage(NexusPreferences.Keys.calendarEventsInTodayEnabled) var calendarEventsEnabled = false
    @AppStorage(NexusPreferences.Keys.agentEnabled) private var agentEnabled = true
    // Internal (not `private`): read from the `+Standalone` extension file.
    @AppStorage(NexusPreferences.Keys.workspaceDisplayName) var workspaceDisplayName: String = ""
    #if os(macOS)
    @Environment(\.openSettings) var openSettings
    #endif
    @Query(sort: \Project.name) private var taskFilterProjects: [Project]
    @Query(sort: \ProjectSection.orderIndex) private var taskFilterSections: [ProjectSection]
    @Query(sort: \SavedFilter.orderIndex) private var taskFilterSavedFilters: [SavedFilter]

    let selection: Binding<TodayNavSelection>?
    // Internal (not `private`): read from the `+Standalone` extension file.
    let showsNavigationRail: Bool
    private let chrome: TodayDashboardChrome
    public let inboxUnreadCount: Int
    public let onInboxUnreadCountChanged: ((Int) -> Void)?
    public let onOpenInboxItem: ((InboxItem) -> Void)?
    // §1a control mode: the Mac shell hoists the Inbox filter into its
    // top-bar band. nil = no host hoist (iOS / standalone) → InboxView
    // keeps its own internal filter owner. Pure presentation routing.
    private let inboxActiveFilter: Binding<InboxFilter>?
    public let onInboxItemsChanged: (([InboxItem]) -> Void)?
    public let onOpenTask: ((TaskItem) -> Void)?
    private let meetingsContent: (() -> AnyView)?
    public let onOpenCapture: (CapturePane.Mode) -> Void
    public let onOpenCommandPalette: () -> Void
    public let onOpenAgent: (() -> Void)?
    let forceCompactLayout: Bool
    let showsCompactCaptureFAB: Bool
    @State private var localSelection: TodayNavSelection = .today
    // Internal (not `private`): read from the `+Standalone` extension file.
    @State var scheduleTasks: [TaskItem] = []
    // Embedded-Today status sections (TODAY / AWAITING YOU / LATER).
    // Separate from `scheduleTasks` so the standalone schedule + day-progress
    // path keeps its own feed untouched. Internal: read from +EmbeddedToday.
    @State var embeddedTodayTasks: [TaskItem] = []
    @State var embeddedAwaiting: [AwaitingEntry] = []
    @State var embeddedLaterTasks: [TaskItem] = []
    // Embedded-Today completion-error + cascade-confirmation surface, mirroring
    // `TaskListView`'s `error`/`cascadePrompt` contract. Internal: written from
    // the +EmbeddedToday extension's repository actions.
    @State var embeddedError: String?
    @State var embeddedCascadePrompt: CascadeCompletionPrompt?
    // Internal (not `private`): read from the `+Standalone` extension file.
    @State var todaysEvents: [CalendarEvent] = []
    // Calendar/Motion-AI blocks for today (spec §7), read via NexusCore.
    @State var scheduleBlocks: [ScheduledBlock] = []
    // Forward-looking deadline-risk signal (spec §19.1 D1); see +EmbeddedAlerts.
    @State var deadlineRiskSummary = DeadlineRiskSummary(atRiskTaskIDs: [], tightTaskIDs: [], mostUrgent: nil)
    @State var deadlineRiskTopTask: TaskItem?
    @State private var digestText: String = ""
    @State private var digestTimestamp: Date = .now
    @State private var heroService: HeroBriefService?
    @State private var reloadGeneration = 0
    // Internal (not `private`): bound from the `+Standalone` extension file.
    @State var taskFilter: TaskFilter = .all  // .upcoming hides overdue/today/undated → empty Tasks view

    public init(
        selection: Binding<TodayNavSelection>? = nil,
        showsNavigationRail: Bool = true,
        chrome: TodayDashboardChrome = .standalone,
        inboxUnreadCount: Int = 0,
        onInboxUnreadCountChanged: ((Int) -> Void)? = nil,
        onOpenInboxItem: ((InboxItem) -> Void)? = nil,
        inboxActiveFilter: Binding<InboxFilter>? = nil,
        onInboxItemsChanged: (([InboxItem]) -> Void)? = nil,
        onOpenTask: ((TaskItem) -> Void)? = nil,
        meetingsContent: (() -> AnyView)? = nil,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void = { _ in },
        onOpenCommandPalette: @escaping () -> Void = {},
        onOpenAgent: (() -> Void)? = nil,
        forceCompactLayout: Bool = false,
        showsCompactCaptureFAB: Bool = true
    ) {
        self.selection = selection
        self.showsNavigationRail = showsNavigationRail
        self.chrome = chrome
        self.inboxUnreadCount = inboxUnreadCount
        self.onInboxUnreadCountChanged = onInboxUnreadCountChanged
        self.onOpenInboxItem = onOpenInboxItem
        self.inboxActiveFilter = inboxActiveFilter
        self.onInboxItemsChanged = onInboxItemsChanged
        self.onOpenTask = onOpenTask
        self.meetingsContent = meetingsContent
        self.onOpenCapture = onOpenCapture
        self.onOpenCommandPalette = onOpenCommandPalette
        self.onOpenAgent = onOpenAgent
        self.forceCompactLayout = forceCompactLayout
        self.showsCompactCaptureFAB = showsCompactCaptureFAB
    }

    public var body: some View {
        ZStack {
            // Embedded in the Nexus shell: the shell already paints the
            // wallpaper organism, so the dashboard must not double it.
            if chrome == .standalone {
                NexusWallpaper()
            }

            #if os(iOS)
            if forceCompactLayout || horizontalSizeClass == .compact {
                compactBody
            } else {
                regularBody
            }
            #else
            regularBody
            #endif
        }
        .modifier(DashboardFrame(chrome: chrome))
        .task { await reloadScheduleData() }
        .task(id: calendarEventsEnabled) { await reloadScheduleData() }
        .reloadOnStoreChange { _Concurrency.Task { await reloadScheduleData() } }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            _Concurrency.Task { await reloadScheduleData() }
        }
    }

    var activeSelection: Binding<TodayNavSelection> {
        selection ?? $localSelection
    }

    @ViewBuilder
    private var regularBody: some View {
        switch chrome {
        case .embedded:
            embeddedRegularBody
        case .standalone:
            standaloneRegularBody
        }
    }

    /// Mounted inside the Nexus shell: no wide sidebar (the icon-rail
    /// replaces it) and no in-column top-bar pill (the shell provides it).
    /// The route content gets a real `minWidth` so it can never compress
    /// behind the 320pt right rail — the pre-existing render bug fix.
    private var embeddedRegularBody: some View {
        // Audit B3: the rail is the single global right rail on routes with
        // no right column of their own, but yields on `inbox` / `meetings`,
        // which own a right pane (double-rail otherwise). When suppressed,
        // `content` simply fills the freed width. Hoisted to a `let` so the
        // `if` condition is single-line (both swiftlint `opening_brace` and
        // swift-format are satisfied — wrapped-condition brace placement
        // disagrees between the two strict gates).
        let showsTimelineRail =
            TodayDashboardContentRoute
            .route(for: activeSelection.wrappedValue)
            .showsEmbeddedTimelineRail
        return HStack(spacing: 0) {
            content
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if showsTimelineRail {
                // MP-2 slice-4: the embedded right rail is the Lab `DayTimeline`
                // Canvas (see `+EmbeddedTimeline.swift`); flipping this line back
                // to `rightRail.frame(width: 320)` fully reverses slice-4. The
                // oracle's "since you last looked" delta-strip below the timeline
                // is INTENTIONALLY OMITTED (it needs persisted last-viewed state —
                // new backend the §5 invariants + `no_canvas_emulation_without_backend`
                // forbid). Tracked into MP-2.2 / MP-6.5; rail is `DayTimeline`-only.
                embeddedTimelineRail
                    // Inset card matching the Inbox reader-pane margins (the
                    // reference right-pane idiom); was full-bleed / "stretched".
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                    .padding(.trailing, 26)
            }
        }
    }

    // Internal (not `private`): called from the `+Standalone` extension file.
    var mainColumn: some View {
        VStack(spacing: 0) {
            NexusTopBar(crumbs: ["Personal", title], onCmdK: onOpenCommandPalette) {
                HStack(spacing: 6) {
                    if activeSelection.wrappedValue == .inbox {
                        NexusButton(variant: .ghost, size: .sm, action: markInboxRead) {
                            HStack(spacing: 4) {
                                Image(systemName: "envelope.open")
                                Text("Mark read")
                            }
                        }
                    }

                    if canOpenAgent {
                        NexusButton(variant: .ghost, size: .sm, action: openAsk) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(NexusColor.Text.primary)
                                Text("Ask")
                            }
                        }
                    }

                    NexusButton(variant: .primary, size: .sm, action: openTaskCapture) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New")
                        }
                    }
                }
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Route content with a cross-fade between nav destinations (audit C1).
    ///
    /// First attempt relied solely on the nav-rail's ambient
    /// `withAnimation(NexusMotion.nav)` reaching this deep identity swap; it
    /// did not propagate reliably (user: "C1 was not working"). Now the
    /// cross-fade is self-contained: an explicit `.animation(_:value:)`
    /// keyed on the resolved route drives the `.id`/`.transition(.opacity)`
    /// swap regardless of how `selection` changed (rail tap, ⌘⇧A, a
    /// notification handler), so it no longer depends on an ambient
    /// transaction. `.id` changes only when the route changes (the switch
    /// already swaps view type per route) so there is no extra in-route
    /// state teardown. A small vertical settle is added to the opacity so
    /// the transition is perceptible on two mostly-dark screens.
    private var content: some View {
        let route = TodayDashboardContentRoute.route(for: activeSelection.wrappedValue)
        return
            routeSwitch
            .id(route)
            .transition(
                .opacity.combined(with: .offset(y: 6))
            )
            .animation(NexusMotion.standard, value: route)
    }

    @ViewBuilder
    private var routeSwitch: some View {
        switch TodayDashboardContentRoute.route(for: activeSelection.wrappedValue) {
        case .today:
            // Embedded = status-sectioned Lab organism; standalone/iOS-compact
            // keep the original greeting+day-progress+schedule (see +EmbeddedToday).
            switch chrome {
            case .embedded:
                embeddedTodayContent
            case .standalone:
                todayContent
            }
        case .inbox:
            InboxView(
                activeFilter: inboxActiveFilter,
                onUnreadCountChanged: { count in
                    onInboxUnreadCountChanged?(count)
                },
                onItemsChanged: { items in
                    onInboxItemsChanged?(items)
                },
                onOpen: { item in
                    onOpenInboxItem?(item)
                }
            )
        case .meetings:
            if let meetingsContent {
                meetingsContent()
            } else {
                placeholderScroll(
                    eyebrow: "Meetings",
                    title: "Meetings unavailable",
                    body: "The app shell has not provided a Meetings surface."
                )
            }
        case .tasks:
            // Freed column (the always-empty DAY rail is dropped for `.tasks`):
            // Linear-style rows fill the full content width, scrollbar at the
            // window edge. (An earlier width cap left a lopsided void + a
            // floating scrollbar on wide monitors — worse than the drift it
            // tried to fix.) `.tasks` case only.
            TaskListView(filter: taskFilter, onSelect: onOpenTask)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Route gutter = chrome gutter (18); matches Today + Inbox (was 28).
                .padding(.horizontal, 18)
        case .productivity:
            ProductivityDashboardView()
        case .settings:
            settingsRoute
        }
    }

    // Internal (not `private`): called from the `+Standalone` extension file.
    var rightRail: some View {
        rightRailContent(
            digestText: digestText,
            digestTimestamp: Self.digestTimeFormatter.string(from: digestTimestamp)
        )
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NexusColor.Background.base.opacity(0.8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(width: 1)
        }
    }

    @MainActor
    private func digestText(input: DigestInput, now: Date) async -> String {
        if agentEnabled, let agentBriefService {
            return await agentBriefService.brief(for: input.agentBriefRequest(now: now))
        }
        return await legacyDigestText(input: input, now: now)
    }

    @MainActor
    private func legacyDigestText(input: DigestInput, now: Date) async -> String {
        guard let aiRouter else {
            return ""
        }
        if heroService == nil {
            heroService = HeroBriefService(router: aiRouter)
        }
        return await heroService?.brief(
            for: input.counts,
            firstTitles: input.firstTitles,
            now: now
        ) ?? ""
    }

    private var title: String {
        switch activeSelection.wrappedValue {
        case .today:
            return "Today"
        case .inbox:
            return "Inbox"
        case .meetings:
            return "Meetings"
        case .tasks:
            return taskFilterTitle
        // Agent/Notes/Calendar/People are full shell destinations mounted directly
        // in the app shell, so these titles are unreached on the app path (the
        // oracle Agent top bar reads "Nexus"); defensive plumbing parity only.
        case .agent: return "Nexus"
        case .notes: return "Notes"
        case .calendar: return "Calendar"
        case .people: return "People"
        case .stats:
            return "Stats"
        case .settings:
            return "Settings"
        }
    }

    // Internal (not `private`): read from the `+Standalone` extension file.
    var taskFilterTitle: String {
        taskFilter.resolvedDisplayTitle(
            projectName: { projectID in
                projectName(projectID)
            },
            sectionName: { projectID, sectionID in
                guard let section = sectionName(projectID: projectID, sectionID: sectionID) else { return nil }
                guard let project = projectName(projectID) else { return section }
                return "\(project) / \(section)"
            },
            savedFilterName: { filterID in
                savedFilterName(filterID)
            }
        )
    }

    // Internal (not `private`): the embedded-Today NowCard subtitle reuses
    // this existing project-name lookup. NOT `public` — the §5 surface-area
    // guard only forbids new `public ` declarations on this file.
    func projectName(_ id: UUID) -> String? {
        taskFilterProjects.first {
            $0.id == id && $0.deletedAt == nil && $0.archivedAt == nil
        }?.name
    }

    private func savedFilterName(_ id: UUID) -> String? {
        taskFilterSavedFilters.first {
            $0.id == id && $0.deletedAt == nil
        }?.name
    }

    private func sectionName(projectID: UUID, sectionID: UUID) -> String? {
        taskFilterSections.first {
            $0.id == sectionID && $0.projectID == projectID && $0.deletedAt == nil
        }?.name
    }

    @MainActor
    func reloadScheduleData() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let now = Date.now
        let events = await Self.calendarEvents(
            now: now,
            enabled: calendarEventsEnabled,
            provider: calendarProvider
        )
        await refreshDeadlineRisk(now: now)  // spec §19.1 D1; see +EmbeddedAlerts
        do {
            let input = try Self.digestInput(now: now, modelContext: modelContext)
            let sections = try Self.embeddedTodaySections(now: now, modelContext: modelContext)
            // A9: the digest (AI brief) drives `rightRail`, mounted ONLY in
            // `standaloneRegularBody` (Mac/iPad regular). Embedded/iOS-compact
            // paths read `scheduleTasks`/`todaysEvents`, not `digestText`, so the
            // async AI call is skipped when `chrome == .embedded` (no behaviour change).
            let digest: String
            if chrome != .embedded {
                digest = await digestText(input: input, now: now)
            } else {
                digest = digestText  // preserve prior value; never displayed
            }
            let blocks = Self.scheduledBlocks(now: now, modelContext: modelContext)
            guard generation == reloadGeneration else { return }
            scheduleTasks = input.today
            scheduleBlocks = blocks
            embeddedTodayTasks = sections.today
            embeddedAwaiting = sections.awaiting
            embeddedLaterTasks = sections.later
            if chrome != .embedded {
                digestText = digest
                digestTimestamp = now
            }
            todaysEvents = events
            // Clear any prior load failure: a transient throw that later
            // succeeds must drop the inline error so the achievement
            // empty-state can earn its way back. Mirrors how the
            // +EmbeddedToday action handlers clear `embeddedError` on success.
            embeddedError = nil
        } catch {
            guard generation == reloadGeneration else { return }
            scheduleTasks = []
            embeddedTodayTasks = []
            embeddedAwaiting = []
            embeddedLaterTasks = []
            if chrome != .embedded {
                digestText = ""
                digestTimestamp = now
            }
            todaysEvents = events
            // A data-load failure must surface as the inline error row, NOT
            // as the celebratory "All clear" achievement: with all
            // buckets zeroed and nothing pinned the empty-state gate would
            // otherwise fire and falsely reward the user on a FAILURE.
            // Setting `embeddedError` makes `embeddedTodayIsEmpty`'s
            // `embeddedError == nil` term false → the sectioned branch runs
            // and `embeddedErrorRow` shows the failure. Same
            // `String(describing:)` idiom slice-2's action handlers use.
            embeddedError = String(describing: error)
        }
    }

}

// `TodayDashboard` digest/schedule static data helpers live in the sibling
// `TodayDashboard+DigestData.swift` (extracted for `file_length` headroom).
