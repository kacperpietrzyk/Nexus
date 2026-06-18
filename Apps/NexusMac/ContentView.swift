import CalendarFeature
import CommandPaletteShell
import InboxShell
import NexusAI
import NexusAgent
import NexusCore
import NexusMeetings
import NexusUI
import NotesFeature
import PeopleFeature
import SwiftData
import SwiftUI
import TasksFeature

// The Mac dashboard shell mounts one full-screen destination per feature
// (Today/Inbox/Meetings/Tasks/Notes/Calendar/Agent/Stats/Settings) inside the
// Liquid chrome (`LiquidAppShell` + `LiquidSidebar` + `LiquidToolbar`); it
// grows by an `.onReceive` + helper per cross-feature affordance by design —
// the same structural growth that disables `file_length` on the iOS shell.
// The daily-note (O4) wiring crossed 600 lines.
// swiftlint:disable file_length
struct ContentView: View {
    // Internal (not `private`): read from the `ContentView+LiquidToday` extension.
    @Environment(\.modelContext) var modelContext
    @Environment(\.taskRepository) private var taskRepository
    @Environment(\.focusModeState) private var focusModeState
    @Environment(\.agentChatViewModel) private var agentViewModel
    // Internal (not `private`): read from the `ContentView+LiquidToday` extension.
    @Environment(\.agentBriefService) var agentBriefService
    // Internal (not `private`): read from the `ContentView+LiquidMeetings` extension.
    @Environment(\.meetingsComposition) var meetingsComposition
    @Environment(\.meetingNavigationRouter) var meetingNavigationRouter
    // Internal (not `private`): read from the `ContentView+LiquidToday` extension.
    @AppStorage(NexusPreferences.Keys.agentEnabled) var agentEnabled = true
    @Environment(\.modelDownloadManager) private var modelDownloadManager
    // Internal: read from the `ContentView+LiquidMeetings` extension for in-app
    // helper recording control (cancel/pause), re-homed from the deleted MeetingsTabView.
    @Environment(\.meetingHelperControl) var meetingHelperControl

    // Internal (not `private`): read from the `ContentView+LiquidToday` extension.
    @State var selection: TodayNavSelection = .today
    // Internal: read from the `ContentView+CaptureAndPeek` extension.
    @State var selectedTask: TaskItem?
    @State private var customSnoozeTask: TaskItem?
    // Not `private`: read by `commandPaletteOverlay` in the ContentView+CaptureAndPeek
    // extension (sibling file), mirroring `capturePresented`.
    @State var commandPalettePresented = false
    // Internal (not private): read by `captureOverlay` in the sibling extension.
    @State var capturePresented = false
    @State var captureMode: CapturePane.Mode = .task
    @State private var inboxUnreadCount = 0
    // §1a control mode (Inbox): the filter-tab control was relocated from
    // the Inbox list-panel header into the shell's top-bar band, so its
    // active selection + the per-category counts the oracle tab idiom shows
    // are hoisted here. `inboxItems` is the SAME already-loaded set the list
    // renders (handed up via `InboxView.onItemsChanged`) — no new query.
    @State private var inboxActiveFilter: InboxFilter = .all
    @State private var inboxItems: [InboxItem] = []
    // TRUE inbox total (sum of every source's count, uncapped). The Inbox list
    // is now windowed, so `inboxItems` is only a page — the "All" filter tab
    // reads this instead so its count stays the real total. Maintained by
    // `reloadInboxCount` (the total only changes on a store write, which that
    // store-change path already covers).
    @State private var inboxTotalCount = 0
    // Calendar surface view-model. Lazily built once from the live container +
    // the shared EventKit provider so its scope/anchor state survives rail
    // switches. Internal (not `private`): read from `ContentView+LiquidCalendar`.
    @State var calendarViewModel: CalendarViewModel?
    // Shared data feed for the Liquid Today screen (Task 5): one model drives both
    // the main column and the inspector slot. Internal: see `ContentView+LiquidToday`.
    @State var liquidTodayModel = LiquidTodayModel()
    // Shared data feed for the Liquid Projects screen (Task 8); same one-model/
    // two-columns shape. Internal: see `ContentView+LiquidProjects`.
    @State var liquidProjectsModel = LiquidProjectsModel()
    // Shared data feed for the Liquid Meetings screen (Task 10); same shape.
    // Internal: see `ContentView+LiquidMeetings`.
    @State var liquidMeetingsModel = LiquidMeetingsModel()
    // Quick Capture draft, hoisted (not inspector @State) so a half-typed capture
    // survives destination switches (the inspector slot unmounts off-Today).
    @State var todayCaptureText = ""
    // Session-stable dismiss flag for the AssistantUpdateBand: hoisted here so
    // "Later" survives destination switches (the agent destination unmounts/remounts).
    // Internal (not `private`): passed as @Binding into AgentContentBand in the
    // ContentView+AgentShell extension.
    @State var assistantBandDismissed = false

    var body: some View {
        Group {
            if let state = activeFocusState {
                focusBody(state: state)
            } else {
                dashboardBody
            }
        }
        .background(LiquidWindowTransparency())
        .task { await observeMeetingNavigation() }
    }

    @ViewBuilder
    private func focusBody(state: FocusModeState) -> some View {
        if let task = focusedTask(for: state) {
            FocusView(task: task)
        } else {
            dashboardBody
                .task(id: state.pinnedTaskID) { @MainActor in
                    state.exit()
                }
        }
    }

    @ViewBuilder
    private var dashboardBody: some View {
        // Notification routing lives here; the chrome (overlays/sheets/tasks)
        // is staged in `dashboardChrome` — one long modifier chain blew the
        // type-checker's budget once the daily-note receive (O4) was added,
        // the same reason `appShell` is extracted below.
        dashboardChrome
            .onReceive(NotificationCenter.default.publisher(for: .nexusOpenCommandPalette)) { _ in
                commandPalettePresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusOpenCapture)) { notification in
                captureMode = notification.object as? CapturePane.Mode ?? .task
                capturePresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusGoToToday)) { _ in
                navigate(to: .today)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusGoToInbox)) { _ in
                navigate(to: .inbox)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusGoToMeetings)) { _ in
                navigate(to: .meetings)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusGoToTasks)) { _ in
                navigate(to: .tasks)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusToggleAgentSidebar)) { _ in
                // MP-3.2 slice 1: Agent is now a full nav-rail shell
                // destination, not a right-side HSplitView pane. ⌘⇧A
                // navigates to it (the notification NAME is kept as-is —
                // renaming is out-of-scope blast radius). The §1
                // "inspector ⊥ Agent" invariant is enforced by the single
                // `.onChange(of: selection)` chokepoint below — this handler
                // stays minimal (single source of truth, no duplicate
                // `selectedTask` clear here). No-op when there is no Agent
                // view-model to mount.
                guard agentViewModel != nil else { return }
                navigate(to: .agent)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusGoToStats)) { _ in
                navigate(to: .stats)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusGoToSettings)) { _ in
                navigate(to: .settings)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusOpenDailyNote)) { _ in
                openTodaysDailyNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusCompleteSelectedTask)) { _ in
                completeSelectedTask()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusSnoozeSelectedTask)) { _ in
                snoozeSelectedTask()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nexusToggleSelectedTaskFocus)) { _ in
                toggleSelectedTaskFocus()
            }
            .onChange(of: selection) { _, newValue in
                // §1 "inspector ⊥ Agent" single chokepoint: the Agent
                // destination owns the whole content slot, so clear any
                // selected task on EVERY transition into `.agent` — covers
                // the ⌘⇧A handler, a direct `sparkles` rail tap, and any
                // future programmatic writer. Keeps state genuinely clean,
                // not merely visually masked by the inspector predicate.
                if newValue == .agent {
                    selectedTask = nil
                }
            }
    }

    /// The shell + window chrome (overlays, sheets, bootstrap tasks), staged out
    /// of `dashboardBody` so neither modifier chain exceeds the type-checker's
    /// budget. Behavior-identical to the previous single chain.
    private var dashboardChrome: some View {
        // Liquid chrome (Task 3): the old `NexusWallpaper` + 54pt `NexusNavRail`
        // + `NexusShell` band stack is replaced by `LiquidAppShell` — three
        // floating glass columns over the transparent macOS window backdrop. The sidebar
        // binds to the SAME `TodayNavSelection` state through the
        // `navigate(to:)` chokepoint, and a destination still owns the whole
        // content slot, exclusive of the task-detail inspector (§1 invariant
        // "inspector ⊥ Agent" — enforced by the `.onChange` in `dashboardBody`,
        // unchanged).
        appShell
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(Color.clear, for: .window)
            // List stays FULL-WIDTH; task detail opens as a CENTERED MODAL over a
            // dimmed scrim (see `taskModal`) — the old trailing peek was too narrow
            // for the inspector's content. Gated on the UNCHANGED `inspectorBinding`
            // predicate (§1 "inspector ⊥ Agent" + its test hold).
            .overlay { taskModal }
            .animation(DS.Motion.standard, value: inspectorBinding.wrappedValue)
            .sheet(item: $customSnoozeTask) { task in
                CustomSnoozeSheet(task: task)
            }
            .onOpenURL { url in handleOpenURL(url) }
            .overlay { commandPaletteOverlay }
            .overlay { captureOverlay }
            .task {
                await bootstrapNavigation()
                await reloadInboxCount()
            }
            // The unread badge tracks Inbox DATA, which changes on a store write —
            // not on navigation. Recompute on store-change (the registry caches
            // allItems and self-invalidates on didSave) instead of on every
            // `selection` change, which re-materialized the whole inbox + walked
            // the Link graph on each view switch. While the Inbox is open it also
            // reports its own count via onInboxUnreadCountChanged, so this only
            // carries the closed-Inbox case.
            .reloadOnStoreChange {
                _Concurrency.Task { await reloadInboxCount() }
            }
    }

    /// The three/four-column glass frame, extracted from `dashboardBody` so its
    /// long modifier chain doesn't type-check the generic shell construction inline.
    private var appShell: some View {
        LiquidAppShell(
            sidebar: {
                LiquidSidebar(
                    selection: selection,
                    inboxUnreadCount: inboxUnreadCount,
                    onNavigate: { navigate(to: $0) }
                )
            },
            toolbar: {
                LiquidToolbar(
                    leading: { toolbarLeading },
                    onOpenCommandPalette: { commandPalettePresented = true },
                    onOpenInbox: { navigate(to: .inbox) },
                    onOpenCapture: openTaskCapture
                )
            },
            main: { destinationMain },
            // Per-destination inspector (04_LAYOUT_SYSTEM.md §Base shell
            // "RightInspector … optional per page"): Today, Calendar, Projects
            // (while a project is selected), and Meetings mount one; the slots
            // are mutually exclusive by their `selection` guards.
            inspector: todayInspectorSlot ?? calendarInspectorSlot ?? projectsInspectorSlot
                ?? meetingsInspectorSlot
        )
    }

    // MARK: - Liquid chrome slots (Task 3)
    //
    // The old invariant chrome (NexusWallpaper + 54pt NexusNavRail) and the
    // per-destination `NexusShell` band stack were replaced by the
    // `LiquidAppShell` mount in `dashboardBody`. `LiquidSidebar` +
    // `LiquidToolbar` are stable across destination switches; only
    // `toolbarLeading` + `destinationMain` re-specialize per destination.
    // (`NexusShell.swift` and the rest of the superseded chrome were deleted
    // in the Task 12 dead-code pass.)

    /// Per-destination leading toolbar content. Inbox keeps its filter tabs +
    /// Mark Read (formerly the §1a control band); Agent keeps its control
    /// strip (`AgentTopControl`); everything else shows the breadcrumb the old
    /// `NexusTopBar` carried. The old per-destination trailing "New Task"
    /// action is covered by the toolbar's fixed `New` button (same capture
    /// seam).
    @ViewBuilder
    private var toolbarLeading: some View {
        if selection == .inbox {
            HStack(spacing: DS.Space.s) {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    InboxFilterTab(
                        label: filter.displayLabel,
                        // "All" = the true windowed total; the category tabs derive
                        // from the loaded set (no people/digests/mention source is
                        // registered, so those are 0 today regardless of windowing).
                        count: filter == .all ? inboxTotalCount : filter.count(in: inboxItems),
                        isActive: inboxActiveFilter == filter
                    ) {
                        inboxActiveFilter = filter
                    }
                }

                Spacer(minLength: DS.Space.m)

                NexusButton(variant: .ghost, size: .sm, action: markInboxRead) {
                    HStack(spacing: DS.Space.xxs) {
                        Image(systemName: "envelope.open")
                        Text("Mark Read")
                    }
                }
                .help("Mark inbox items read")
                .accessibilityLabel("Mark inbox items read")
            }
        } else if selection == .agent, let agentViewModel {
            AgentTopControl(viewModel: agentViewModel)
        } else if selection == .today {
            LiquidTodayTitle()
        } else {
            LiquidToolbarBreadcrumb(crumbs: ["Personal", shellTitle])
        }
    }

    /// Per-destination page content inside the glass content shell.
    @ViewBuilder
    private var destinationMain: some View {
        if selection == .today {
            // Liquid Today / Command Center (Task 5). Replaces the old
            // `TodayDashboard` mount for `.today` only — Inbox/Tasks/Stats/
            // Settings still route through `dashboardContent` below.
            liquidTodayMain
        } else if selection == .agent, let agentViewModel {
            // Agent owns the whole content slot: thread rail + chat above the
            // real message composer. The same shared upstream `agentViewModel`
            // (`AgentComposition.chatViewModel`, env-injected) drives BOTH
            // `AgentChatView` (inside `AgentThreadRail`) and
            // `AgentBottomInput`, so a `send` from the bottom bar re-renders
            // the message list and `isThinking` flows to both. The composer
            // keeps its established placement padding (it carries its own
            // background + hairline — never re-wrapped in chrome).
            VStack(spacing: 0) {
                // AssistantUpdateBand: shown only when the model is not yet
                // downloaded and the user hasn't dismissed it this session.
                // Rendered in a reactive @ObservedObject wrapper so it hides
                // automatically once the download transitions readiness state.
                AgentContentBand(
                    viewModel: agentViewModel,
                    downloadManager: modelDownloadManager,
                    bandDismissed: $assistantBandDismissed
                )
                AgentThreadRail(viewModel: agentViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                AgentBottomInput(viewModel: agentViewModel)
                    .padding(.horizontal, 26)
                    .padding(.top, 14)
                    .padding(.bottom, DS.Space.xl)
            }
        } else if selection == .projects {
            // Liquid Projects / Execution (Task 8): picker → header + tabs +
            // milestones + Kanban + table; replaces the `ProjectsRootView`
            // mount. See `ContentView+LiquidProjects`.
            liquidProjectsMain
        } else if selection == .meetings {
            // Liquid Meetings / Notes Intelligence (Task 10): list + detail +
            // knowledge column; replaces the `MeetingsTabView` mount. See
            // `ContentView+LiquidMeetings`.
            liquidMeetingsMain
        } else if selection == .notes {
            // Notes content layer (spec §5): list + block editor; owns its own
            // NavigationStack.
            NotesListView()
                .environment(\.notesTaskRepository, taskRepository)
        } else if selection == .calendar {
            // Liquid Calendar / Week Planning (Task 6): custom week grid +
            // scheduling strip; Day/Month re-mount the existing grids. See
            // `ContentView+LiquidCalendar`.
            liquidCalendarMain
        } else if selection == .people {
            // People / Contacts surface (spec §6); owns its own NavigationStack.
            PeopleListView()
        } else if selection == .settings {
            // Native two-pane in-shell Settings (Task 9): reads the
            // `MacSettingsDependencies` bundle NexusMacApp injects into the
            // environment. Replaces the old separate `Settings {}` window.
            LiquidSettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Inbox / Tasks / Stats routes inside `TodayDashboard`
            // (embedded chrome).
            dashboardContent
        }
    }

    private func openTaskCapture() {
        NotificationCenter.default.post(name: .nexusOpenCapture, object: CapturePane.Mode.task)
    }

    private var shellTitle: String {
        switch selection {
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .meetings: return "Meetings"
        case .tasks: return "Tasks"
        case .projects: return "Projects"
        case .notes: return "Notes"
        case .calendar: return "Calendar"
        case .people: return "People"
        // The oracle Agent top bar reads "Nexus"; crumbs are unused in
        // control mode anyway (no `NexusTopBar`), so this is defensive
        // plumbing parity only.
        case .agent: return "Nexus"
        case .stats: return "Stats"
        case .settings: return "Settings"
        }
    }

    private func markInboxRead() {
        NotificationCenter.default.post(name: .nexusMarkInboxRead, object: nil)
    }

    private var dashboardContent: some View {
        TodayDashboard(
            selection: $selection,
            chrome: .embedded,
            inboxUnreadCount: inboxUnreadCount,
            onInboxUnreadCountChanged: { inboxUnreadCount = $0 },
            onOpenInboxItem: { openInboxItem($0) },
            inboxActiveFilter: $inboxActiveFilter,
            onInboxItemsChanged: { inboxItems = $0 },
            onOpenTask: { openTask($0) },
            // `.meetings` mounts the Liquid Meetings screen in
            // `destinationMain` (Task 10) and never reaches this dashboard
            // router anymore — no embedded meetings content to inject.
            meetingsContent: nil,
            onOpenCapture: { mode in
                NotificationCenter.default.post(name: .nexusOpenCapture, object: mode)
            },
            onOpenCommandPalette: {
                commandPalettePresented = true
            },
            onOpenAgent: {
                navigate(to: .agent)
            }
        )
    }

    /// Single chokepoint for ALL nav-destination changes — `LiquidSidebar`
    /// taps (via `onNavigate`) and programmatic writes (goToToday/goToInbox
    /// notifications, ⌘⇧A → Agent, meeting/task routing, the command-palette
    /// bootstrap closures) — so every write shares the same
    /// `withAnimation(DS.Motion.nav)` envelope: content cross-fade +
    /// selection-pill hero-transition (audit C3 follow-up, carried over from
    /// the pre-Liquid `NexusNavRail`). The `.onChange(of: selection)`
    /// "inspector ⊥ Agent" chokepoint still fires regardless — orthogonal,
    /// unaffected.
    /// Internal (not `private`): called from the `ContentView+LiquidToday` extension.
    @MainActor
    func navigate(to destination: TodayNavSelection) {
        withAnimation(DS.Motion.nav) { selection = destination }
    }

    /// Opening a task's detail inspector while the Agent destination is
    /// active navigates back to Today first — the Agent destination owns the
    /// whole content area, so it is mutually exclusive with the task-detail
    /// inspector by construction (preserves the §1 "inspector ⊥ Agent"
    /// render-bug invariant). Today is the safe default landing.
    /// Internal (not `private`): called from the `ContentView+LiquidToday` extension.
    func openTask(_ task: TaskItem) {
        if selection == .agent {
            navigate(to: .today)
        }
        selectedTask = task
    }

    @MainActor
    private func completeSelectedTask() {
        guard let taskRepository, let selectedTask else { return }
        do {
            try TaskCompletionAction.completeOrCascade(selectedTask, repository: taskRepository)
        } catch {}
    }

    @MainActor
    private func snoozeSelectedTask() {
        guard let taskRepository, let selectedTask else { return }
        do {
            try taskRepository.snooze(selectedTask, until: taskRepository.now().addingTimeInterval(3600))
        } catch {}
    }

    @MainActor
    private func toggleSelectedTaskFocus() {
        guard let taskRepository, let selectedTask else { return }
        do {
            try taskRepository.update(selectedTask) { task in
                task.pinnedAsFocus.toggle()
            }
        } catch {}
    }

    private var activeFocusState: FocusModeState? {
        guard let state = focusModeState, state.isInFocus else { return nil }
        return state
    }

    @MainActor
    private func focusedTask(for state: FocusModeState) -> TaskItem? {
        guard let id = state.pinnedTaskID else { return nil }
        return fetchPinnedTask(id: id)
    }

    @MainActor
    private func fetchPinnedTask(id: UUID) -> TaskItem? {
        let taskID = id
        let openStatus = TaskStatus.open.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate {
                $0.id == taskID && $0.deletedAt == nil && $0.statusRaw == openStatus
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    // Internal: read by `taskModal` in the `ContentView+CaptureAndPeek` extension.
    // Defense-in-depth for the §1 "inspector ⊥ Agent" invariant — routes the
    // visibility decision through the pure `InspectorVisibility` predicate so it
    // holds even if state lags a frame and is unit-testable without SwiftUI.
    var inspectorBinding: Binding<Bool> {
        Binding(
            get: {
                InspectorVisibility.shouldShowInspector(
                    selectedTask: selectedTask,
                    selection: selection
                )
            },
            set: { if !$0 { selectedTask = nil } }
        )
    }

    /// O4 "Today's note, one action away": mark the pending open FIRST, then
    /// route to Notes — a mounted `NotesListView` reacts to the notification
    /// `DailyNoteOpenRequest` posts; an unmounted one consumes the pending flag
    /// in its `.task` on appear. Shared by the menu item (⌘⇧D) and the palette.
    @MainActor
    private func openTodaysDailyNote() {
        DailyNoteOpenRequest.shared.request()
        navigate(to: .notes)
    }

    /// O1 graph view, one action away: mark the pending open FIRST, then route
    /// to Notes — same two-path delivery as `openTodaysDailyNote`.
    @MainActor
    private func openNotesGraph() {
        GraphOpenRequest.shared.request()
        navigate(to: .notes)
    }

    private func bootstrapNavigation() async {
        await NotesComposition.bootstrap(
            openDailyNote: { openTodaysDailyNote() },
            openGraph: { openNotesGraph() }
        )
        guard let taskRepository else { return }
        await TasksComposition.bootstrap(
            repository: taskRepository,
            navigation: TaskCommandNavigation(
                goToToday: { navigate(to: .today) },
                goToInbox: { navigate(to: .inbox) },
                openCapture: {
                    NotificationCenter.default.post(name: .nexusOpenCapture, object: CapturePane.Mode.task)
                },
                selectedTask: { selectedTask }
            )
        )
    }

    @MainActor
    private func observeMeetingNavigation() async {
        guard let meetingNavigationRouter else { return }
        if meetingNavigationRouter.selectedMeetingID != nil {
            focusModeState?.exit()
            navigate(to: .meetings)
        }
        for await _ in meetingNavigationRouter.selections {
            focusModeState?.exit()
            navigate(to: .meetings)
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard
            url.scheme == "nexus",
            url.host == "task",
            let last = url.pathComponents.last, last == "snooze",
            url.pathComponents.count >= 3,
            let idString = url.pathComponents.first(where: { UUID(uuidString: $0) != nil }),
            let id = UUID(uuidString: idString)
        else { return }
        _Concurrency.Task { @MainActor in
            let predicate = #Predicate<TaskItem> { $0.id == id }
            let descriptor = FetchDescriptor<TaskItem>(predicate: predicate)
            if let task = try? modelContext.fetch(descriptor).first {
                customSnoozeTask = task
            }
        }
    }

    @MainActor
    private func reloadInboxCount() async {
        // The sidebar badge is the UNREAD count, so it must subtract items the
        // user has marked read — otherwise it re-shows the full total every time
        // it recomputes (e.g. after navigating away from the Inbox), even though
        // InboxView itself shows them read. Reads the same persisted store
        // InboxView writes (id == stable TaskItem.id).
        //
        // Uses the cheap `totalCount()` (a `fetchCount`, no materialization)
        // instead of `allItems()` — the Inbox is windowed now, and recomputing
        // the badge must not re-materialize ~1383 rows. Formula is identical to
        // `InboxView.unreadCount` so the badge doesn't jump on Inbox enter/exit.
        let total = (try? await InboxSourceRegistry.shared.totalCount()) ?? 0
        let read = InboxReadStateStore.shared.load()
        inboxTotalCount = total
        inboxUnreadCount = max(0, total - read.count)
    }

    @MainActor
    private func openInboxItem(_ item: InboxItem) {
        let id = item.id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.id == id && task.deletedAt == nil
            }
        )
        // Route through `openTask` so the inspector/Agent mutual exclusion
        // holds for inbox-opened tasks too (otherwise opening an inbox item
        // while the Agent pane is up reproduces the triple-occupy dead-void).
        guard let task = try? modelContext.fetch(descriptor).first else { return }
        openTask(task)
    }
}

/// A single Inbox filter tab for the §1a control-mode top bar. Structural
/// 1:1 replica of the accepted Inbox oracle's private `InboxTab`
/// (the LabKit oracle, since internalized into NexusUI; the `Lab/` tree was
/// deleted in MP-6), re-toned through the MP-2.2 §2
/// achromatic LabPalette→NexusColor map:
/// `ink→Text.primary`, `read→Text.secondary`, `faint→Text.muted`,
/// `dim→Text.disabled`, active fill→`Background.control` (the chrome
/// selection tier, r1 corners). Not a primitive — a thin
/// token composition, same status as the private `AgentTopControl`.
/// Inter-Medium 12 / IBMPlexMono-Medium 10 are below the `NexusType` scale
/// (which starts at 11 pt caption), so raw `Font.custom` against the
/// process-registered family is the honest §8 stopgap (same path the old
/// `NexusCommandBar` used for its ⌘K kbd chip before the Liquid rewrite).
private struct InboxFilterTab: View {
    let label: String
    let count: Int
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    /// Idle hover wash one step below `glassSelected`, same ladder the Liquid
    /// icon buttons use (03_COMPONENTS.md §IconButton hover #FFFFFF10).
    private var fill: Color {
        if isActive { return DS.ColorToken.glassSelected }
        return hovering ? Color.white.opacity(0.04) : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(DS.FontToken.body)
                Text("\(count)")
                    .font(DS.FontToken.metadata)
                    .monospacedDigit()
                    .foregroundStyle(
                        isActive ? DS.ColorToken.textSecondary : DS.ColorToken.textMuted
                    )
            }
            .foregroundStyle(isActive ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(fill))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isActive ? DS.ColorToken.strokeHairline : .clear, lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        .animation(DS.Motion.selection, value: isActive)
        .accessibilityLabel(label)
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TaskItem.self], inMemory: true)
}
