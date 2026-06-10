import CalendarFeature
import CommandPaletteShell
import InboxShell
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
// Liquid chrome (`LiquidAppShell` + `LiquidSidebar` + `LiquidToolbar`).
struct ContentView: View {
    // Internal (not `private`): read from the `ContentView+LiquidToday` extension.
    @Environment(\.modelContext) var modelContext
    @Environment(\.taskRepository) private var taskRepository
    @Environment(\.focusModeState) private var focusModeState
    @Environment(\.agentChatViewModel) private var agentViewModel
    // Internal (not `private`): read from the `ContentView+LiquidToday` extension.
    @Environment(\.agentBriefService) var agentBriefService
    @Environment(\.meetingsComposition) private var meetingsComposition
    @Environment(\.meetingNavigationRouter) private var meetingNavigationRouter
    // Internal (not `private`): read from the `ContentView+LiquidToday` extension.
    @AppStorage(NexusPreferences.Keys.agentEnabled) var agentEnabled = true

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
    // Calendar/Motion-AI surface (spec §9). Lazily built once from the live
    // container + the shared EventKit provider so its scope/anchor state survives
    // rail switches.
    @State private var calendarViewModel: CalendarViewModel?
    // Shared data feed for the Liquid Today screen (Task 5): one model drives
    // BOTH the main column and the right inspector, so the two slots always
    // render the same load. Owned here (not inside the screen) because the
    // inspector mounts through a separate `LiquidAppShell` slot.
    // Internal (not `private`): shared with the `ContentView+LiquidToday` extension.
    @State var liquidTodayModel = LiquidTodayModel()

    var body: some View {
        Group {
            if let state = activeFocusState {
                focusBody(state: state)
            } else {
                dashboardBody
            }
        }
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
        // Liquid chrome (Task 3): the old `NexusWallpaper` + 54pt `NexusNavRail`
        // + `NexusShell` band stack is replaced by `LiquidAppShell` — three
        // floating glass columns over a dark wallpaper gradient. The sidebar
        // binds to the SAME `TodayNavSelection` state through the
        // `navigate(to:)` chokepoint, and a destination still owns the whole
        // content slot, exclusive of the task-detail inspector (§1 invariant
        // "inspector ⊥ Agent" — enforced by the `.onChange` below, unchanged).
        appShell
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(DS.ColorToken.backgroundApp, for: .window)
            // List stays FULL-WIDTH; task detail opens as a CENTERED MODAL over a
            // dimmed scrim (see `taskModal`) — the old trailing peek was too narrow
            // for the inspector's content. Gated on the UNCHANGED `inspectorBinding`
            // predicate (§1 "inspector ⊥ Agent" + its test hold).
            .overlay { taskModal }
            .animation(NexusMotion.standard, value: inspectorBinding.wrappedValue)
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
            .task(id: selection) {
                await reloadInboxCount()
            }
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
            // "RightInspector … optional per page"): only Today mounts one.
            inspector: todayInspectorSlot
        )
    }

    // MARK: - Liquid chrome slots (Task 3)
    //
    // The old invariant chrome (NexusWallpaper + 54pt NexusNavRail) and the
    // per-destination `NexusShell` band stack were replaced by the
    // `LiquidAppShell` mount in `dashboardBody`. `LiquidSidebar` +
    // `LiquidToolbar` are stable across destination switches; only
    // `toolbarLeading` + `destinationMain` re-specialize per destination.
    // `NexusShell.swift` is left in place (unused) for a later deletion task.

    /// Per-destination leading toolbar content. Inbox keeps its filter tabs +
    /// Mark Read (formerly the §1a control band); Agent keeps its control
    /// strip (`AgentTopControl`); everything else shows the breadcrumb the old
    /// `NexusTopBar` carried. The old per-destination trailing "New Task"
    /// action is covered by the toolbar's fixed `New` button (same capture
    /// seam).
    @ViewBuilder
    private var toolbarLeading: some View {
        if selection == .inbox {
            HStack(spacing: 8) {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    InboxFilterTab(
                        label: filter.displayLabel,
                        count: filter.count(in: inboxItems),
                        isActive: inboxActiveFilter == filter
                    ) {
                        inboxActiveFilter = filter
                    }
                }

                Spacer(minLength: 12)

                NexusButton(variant: .ghost, size: .sm, action: markInboxRead) {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.open")
                        Text("Mark Read")
                    }
                }
                .help("Mark inbox items read")
                .accessibilityLabel("Mark inbox items read")
            }
        } else if selection == .agent, let agentViewModel {
            AgentTopControl(viewModel: agentViewModel)
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
                AgentThreadRail(viewModel: agentViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                AgentBottomInput(viewModel: agentViewModel)
                    .padding(.horizontal, 26)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
            }
        } else if selection == .projects {
            // Projects tier (#10): list → project page (header + lifecycle
            // status + Kanban board). Opening a card routes through `openTask`
            // (inspector ⊥ Agent invariant preserved).
            ProjectsRootView(onOpenTask: { openTask($0) })
        } else if selection == .notes {
            // Notes content layer (spec §5): list + block editor; owns its own
            // NavigationStack.
            NotesListView()
        } else if selection == .calendar {
            // Calendar/Motion-AI surface (spec §9): Month/Week/Day grid +
            // event editor; owns its own header/navigation.
            calendarContent
        } else if selection == .people {
            // People / Contacts surface (spec §6); owns its own NavigationStack.
            PeopleListView()
        } else {
            // Today / Inbox / Tasks / Stats / Settings routes inside
            // `TodayDashboard` (embedded chrome).
            dashboardContent
        }
    }

    private func openTaskCapture() {
        NotificationCenter.default.post(name: .nexusOpenCapture, object: CapturePane.Mode.task)
    }

    @ViewBuilder
    private var calendarContent: some View {
        if let calendarViewModel {
            CalendarView(viewModel: calendarViewModel)
                // Pin the view's structural identity so `destinationMain`
                // branch re-evaluations (e.g. a future per-destination
                // inspector slot changing the enclosing generic shape) never
                // tear down CalendarView's internal @State.
                .id(TodayNavSelection.calendar)
        } else {
            Color.clear
                .onAppear {
                    #if canImport(EventKit) && !os(watchOS)
                    let provider = EventKitCalendarProvider.shared
                    calendarViewModel = CalendarViewModel(
                        context: modelContext,
                        reader: provider,
                        writer: provider,
                        listing: provider
                    )
                    #endif
                }
        }
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
            meetingsContent: meetingsContent,
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

    /// Single chokepoint for *programmatic* nav-destination changes so they
    /// share the rail tap's animated envelope (audit C3 follow-up).
    /// `NexusNavRail` wraps its own tap in `withAnimation(NexusMotion.nav)`,
    /// which is what makes the C1 content cross-fade and the C3
    /// selection-pill hero-transition play. Programmatic writes
    /// (goToToday/goToInbox notifications, ⌘⇧A → Agent, meeting/task
    /// routing, the command-palette bootstrap closures) bypassed that and
    /// snapped; routing every such write through here gives them the
    /// identical slide. The `.onChange(of: selection)` "inspector ⊥ Agent"
    /// chokepoint still fires regardless — orthogonal, unaffected.
    /// Internal (not `private`): called from the `ContentView+LiquidToday` extension.
    @MainActor
    func navigate(to destination: TodayNavSelection) {
        withAnimation(NexusMotion.nav) { selection = destination }
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

    private var meetingsContent: (() -> AnyView)? {
        guard let meetingsComposition, let meetingNavigationRouter else { return nil }
        return {
            AnyView(
                MeetingsTabView(
                    router: meetingNavigationRouter,
                    composition: meetingsComposition
                )
            )
        }
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

    private func bootstrapNavigation() async {
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
        let items = (try? await InboxSourceRegistry.shared.allItems()) ?? []
        let read = InboxReadStateStore.shared.load()
        inboxUnreadCount = items.filter { !read.contains($0.id) }.count
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
/// token composition, same status as the private `NexusCommandBar`.
/// Inter-Medium 12 / IBMPlexMono-Medium 10 are below the `NexusType` scale
/// (which starts at 11 pt caption), so raw `Font.custom` against the
/// process-registered family is the honest §8 stopgap (same path
/// `NexusCommandBar` uses for its ⌘K kbd chip).
private struct InboxFilterTab: View {
    let label: String
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(Font.custom("Inter-Medium", size: 12))
                Text("\(count)")
                    .font(NexusType.metaMono)
                    .monospacedDigit()
                    .foregroundStyle(
                        isActive ? NexusColor.Text.secondary : NexusColor.Text.disabled
                    )
            }
            .foregroundStyle(isActive ? NexusColor.Text.primary : NexusColor.Text.muted)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: NexusRadius.r1)
                    .fill(isActive ? NexusColor.Background.control : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TaskItem.self], inMemory: true)
}
