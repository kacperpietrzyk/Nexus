import CommandPaletteShell
import InboxShell
import NexusAgent
import NexusCore
import NexusMeetings
import NexusUI
import NotesFeature
import SwiftData
import SwiftUI
import TasksFeature

// The Mac dashboard shell mounts one full-screen destination per feature
// (Today/Inbox/Meetings/Tasks/Notes/Agent/Stats/Settings); it grows by a rail
// item + a `dashboardShell` branch + a title case per feature by design — the
// same structural per-feature growth that disables `file_length` on
// `NexusMacApp`. The Notes mount crossed the 600-line threshold.
// swiftlint:disable file_length
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var taskRepository
    @Environment(\.focusModeState) private var focusModeState
    @Environment(\.agentChatViewModel) private var agentViewModel
    @Environment(\.meetingsComposition) private var meetingsComposition
    @Environment(\.meetingNavigationRouter) private var meetingNavigationRouter

    @State private var selection: TodayNavSelection = .today
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
        // Audit C3 hoist "D": the invariant chrome (wallpaper + icon-rail)
        // is composed HERE so it survives `dashboardShell`'s per-destination
        // re-specialization — the rail's pill `matchedGeometryEffect` is
        // never torn down and slides on every transition. Only the right
        // column (`dashboardShell` = NexusShell's band stack) re-specializes;
        // a destination still owns the whole content area and is exclusive
        // of the task-detail inspector (§1 invariant "inspector ⊥ Agent").
        ZStack {
            NexusWallpaper()
            HStack(spacing: 0) {
                navRail
                dashboardShell
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(NexusColor.Background.base, for: .window)
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

    // MARK: - Invariant chrome (audit C3 hoist "D")
    //
    // `NexusWallpaper` + the 54pt `NexusNavRail` are composed HERE, in
    // `dashboardBody`, NOT inside `NexusShell`. `ContentView` does not
    // re-specialize, so the rail (and wallpaper) are never torn down — the
    // rail's selection-pill `matchedGeometryEffect` therefore survives every
    // navigation and SLIDES instead of snapping.
    //
    // HISTORY — A11 → C3. A11 accepted the per-destination NexusShell
    // re-specialization (each `dashboardShell` branch is a distinct generic
    // type; the constrained-extension-init "both-slots" compile-time safety
    // is worth it; AnyView collapse is **still rejected**). Its two cosmetic
    // side-effects were: (a) the bottom bar's @State is torn down with the
    // old specialization (post-B1: the inline composer's in-progress
    // `CapturePaneState` — unsent typed text lost on an Inbox/Agent toggle;
    // still acceptable, not C3 scope); (b) the nav-rail pill snapped because
    // the rail lived inside the rebuilt subtree. C3's first attempt injected
    // a stable `@Namespace` into the still-in-shell rail — that was
    // necessary but NOT sufficient (the old rail was removed without a
    // transition, so the matched source ceased to exist outside the
    // animation envelope; user smoke confirmed it still snapped). C3's
    // converged fix is this structural hoist: the rail is no longer in the
    // re-specialized subtree at all, so (b) is structurally eliminated.
    // (a) is unchanged. `railSelectionNamespace` stays as an additive
    // optional on `NexusNavRail` (iOS/Watch may inject their own; frozen-API
    // rule). Build + lint is the gate; the slide itself is manual-smoke.
    @Namespace private var railSelectionNamespace

    private var railItems: [NexusNavRailItem<TodayNavSelection>] {
        [
            .init(id: .today, systemImage: "circle.dotted", label: "Today"),
            .init(id: .inbox, systemImage: "tray", label: "Inbox", count: inboxUnreadCount),
            .init(id: .meetings, systemImage: "person.wave.2", label: "Meetings"),
            .init(id: .tasks, systemImage: "checkmark.square", label: "Tasks"),
            .init(id: .notes, systemImage: "note.text", label: "Notes"),
            .init(id: .agent, systemImage: "sparkles", label: "Agent"),
            .init(id: .stats, systemImage: "chart.bar", label: "Stats"),
        ]
    }

    private var railSettingsItem: NexusNavRailItem<TodayNavSelection> {
        .init(id: .settings, systemImage: "gearshape", label: "Settings")
    }

    /// The invariant icon-rail. Lives in `ContentView` (stable) so its
    /// pill `matchedGeometryEffect` is never regenerated. `NexusNavRail`
    /// wraps the `active` mutation in `withAnimation(NexusMotion.nav)`
    /// internally, so a rail tap animates; programmatic nav animates via
    /// the `navigate(to:)` chokepoint.
    private var navRail: some View {
        NexusNavRail(
            items: railItems,
            active: $selection,
            logoTitle: "Nexus",
            bottomItem: railSettingsItem,
            selectionNamespace: railSelectionNamespace
        )
    }

    @ViewBuilder
    private var dashboardShell: some View {
        if selection == .inbox {
            // §1a control mode: bespoke top bar = relocated filter tabs
            // (leading) + the existing Read + New actions (trailing). The
            // oracle's static right-side timestamp is dropped (§10 — no
            // backend). `NexusTopBar` is NOT used.
            NexusShell(
                crumbs: ["Personal", shellTitle],
                onOpenCommandPalette: { commandPalettePresented = true },
                onOpenCapture: { mode in
                    NotificationCenter.default.post(name: .nexusOpenCapture, object: mode)
                },
                topControl: { inboxTopControl },
                content: { dashboardContent }
            )
        } else if selection == .agent, let agentViewModel {
            // §1a control mode + §1c surface-input mode: Agent's oracle
            // `LabTopBar` is an interactive control strip → control mode (NOT
            // `NexusTopBar`); its oracle bottom band is a real message
            // composer ("Napisz do Nexusa…"), so the shell renders the
            // surface-supplied `AgentBottomInput` in place of the generic
            // `NexusCommandBar` (§1c). `AgentChatView`'s now-redundant inner
            // `AgentInputBar` was removed (its `else` branch is just
            // `messageList`), closing the slice-1 transient double-bottom-bar
            // seam. The same shared upstream `agentViewModel`
            // (`AgentComposition.chatViewModel`, env-injected) drives BOTH
            // `AgentChatView` (content) and `AgentBottomInput` (bottom band):
            // `AgentChatView` wraps it once via `StateObject(wrappedValue:)`
            // returning the same singleton, and `AgentBottomInput` observes
            // it via `@ObservedObject`, so a `send` from the bottom bar
            // re-renders the message list and `isThinking` flows to both.
            // Thread management on macOS: `AgentThreadRail` fronts the chat with
            // a persistent, selectable/archivable thread list (see its doc for
            // why this is an `HStack` rail, not a nested `NavigationSplitView`).
            NexusShell(
                crumbs: ["Personal", shellTitle],
                onOpenCommandPalette: { commandPalettePresented = true },
                onOpenCapture: { mode in
                    NotificationCenter.default.post(name: .nexusOpenCapture, object: mode)
                },
                topControl: { AgentTopControl(viewModel: agentViewModel) },
                bottomBar: { AgentBottomInput(viewModel: agentViewModel) },
                content: { AgentThreadRail(viewModel: agentViewModel) }
            )
        } else if selection == .notes {
            // Notes content layer (spec §5): a full shell destination mounting
            // the NotesFeature list + block editor. `NotesListView` owns its own
            // NavigationStack, so it slots straight into the shell content area.
            NexusShell(
                crumbs: ["Personal", shellTitle],
                onOpenCommandPalette: { commandPalettePresented = true },
                onOpenCapture: { mode in
                    NotificationCenter.default.post(name: .nexusOpenCapture, object: mode)
                },
                topControl: { EmptyView() },
                content: { NotesListView() }
            )
        } else {
            NexusShell(
                crumbs: ["Personal", shellTitle],
                onOpenCommandPalette: { commandPalettePresented = true },
                onOpenCapture: { mode in
                    NotificationCenter.default.post(name: .nexusOpenCapture, object: mode)
                },
                topTrailing: { shellTopTrailing },
                content: { dashboardContent }
            )
        }
    }

    /// §1a control-mode top-bar content for Inbox: filter tabs leading
    /// (matching the accepted Inbox oracle's `InboxTab` idiom 1:1
    /// via the §2 achromatic token map) + the existing Read + New actions
    /// trailing. No new primitive — a thin token composition, mirroring the
    /// `NexusCommandBar` precedent in `NexusShell.swift`.
    @ViewBuilder
    private var inboxTopControl: some View {
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

        newTaskButton
    }

    /// The capture-launching "New" button, shared verbatim by
    /// `inboxTopControl` and `shellTopTrailing` (was duplicated byte-for-byte).
    private var newTaskButton: some View {
        NexusButton(variant: .primary, size: .sm, action: openTaskCapture) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("New Task")
            }
        }
        .help("New task (⌘N)")
        .accessibilityLabel("New task")
    }

    @ViewBuilder
    private var shellTopTrailing: some View {
        newTaskButton
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
        case .notes: return "Notes"
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
    @MainActor
    private func navigate(to destination: TodayNavSelection) {
        withAnimation(NexusMotion.nav) { selection = destination }
    }

    /// Opening a task's detail inspector while the Agent destination is
    /// active navigates back to Today first — the Agent destination owns the
    /// whole content area, so it is mutually exclusive with the task-detail
    /// inspector by construction (preserves the §1 "inspector ⊥ Agent"
    /// render-bug invariant). Today is the safe default landing.
    private func openTask(_ task: TaskItem) {
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
