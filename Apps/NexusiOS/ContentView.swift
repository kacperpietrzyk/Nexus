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
import UIKit

// The iOS root shell mounts one tab/destination per feature
// (Today/Inbox/Tasks/Notes/Calendar/People/Agent/Meetings/Settings) in both the compact tab bar
// and the regular-width split; it grows by a tab + a `regularDetail` case + a
// nav item per feature by design — the same structural per-feature growth that
// disables `file_length` on `NexusiOSApp`. The Notes mount crossed 600 lines.
// swiftlint:disable file_length
struct ContentView: View {

    fileprivate enum NexusTab: Hashable {
        case today, inbox, tasks, projects, notes, calendar, people, meetings, agent, stats, settings
    }

    let cloudKitEnabled: Bool
    let containerIdentifier: String
    let permissionState: NotificationPermissionState
    let agentSettingsContext: AgentSettingsContext?
    let manageModelsContent: AnyView?
    let onExportRequested: () -> Void

    @Environment(\.aiRouter) private var aiRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var taskRepository
    @Environment(\.agentChatViewModel) private var agentViewModel
    @Environment(\.meetingsComposition) private var meetingsComposition
    @Environment(\.focusModeState) private var focusModeState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    // Liquid Today (ported from macOS): shared model + the daily-brief seam.
    @Environment(\.agentBriefService) var agentBriefService
    @AppStorage(NexusPreferences.Keys.agentEnabled) var agentEnabled = true

    @State var liquidTodayModel = LiquidTodayModel()
    // Liquid Projects (ported from macOS): one shared model drives the Projects
    // screen + its Overview dashboard, the same sharing shape as Liquid Today.
    @State var liquidProjectsModel = LiquidProjectsModel()
    @State private var selectedTab: NexusTab = ContentView.initialTab()

    /// DEBUG-only: lets the screenshot/QA loop deep-open a specific tab via the
    /// `NEXUS_INITIAL_TAB` launch env var (no tap automation in the harness).
    /// Always `.today` in Release.
    private static func initialTab() -> NexusTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["NEXUS_INITIAL_TAB"] {
        case "tasks": return .tasks
        case "projects": return .projects
        case "notes": return .notes
        case "inbox": return .inbox
        case "agent": return .agent
        case "calendar": return .calendar
        case "people": return .people
        case "meetings": return .meetings
        case "stats": return .stats
        case "settings": return .settings
        default: return .today
        }
        #else
        return .today
        #endif
    }
    // Calendar/Motion-AI surface (spec §9). Lazily
    // built once so scope/anchor state survives tab switches.
    @State private var calendarViewModel: CalendarViewModel?
    // Internal (not private) so the `ContentView+CaptureAndPeek` extension file
    // can drive the regular-width task-detail peek + Quick Capture overlays.
    @State var selectedTask: TaskItem?
    @State private var inboxUnreadCount = 0
    @State var capturePresented = false
    @State var captureMode: CapturePane.Mode = .task
    @State private var customSnoozeTask: TaskItem?
    @State private var quietHoursState = QuietHoursViewState()
    @State private var commandPalettePresented = false
    @State private var pencilCapturePresented = false

    var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// Decision #2/#3: on regular width (iPad) the task detail + Quick Capture
    /// are presented as floating overlays on the detail pane (Mac peek idiom),
    /// not as sheets. These bindings gate the compact-only `.sheet`s so they
    /// never fire on iPad, where the overlay carries the surface instead.
    private var compactSelectedTask: Binding<TaskItem?> {
        Binding(
            get: { isRegularWidth ? nil : selectedTask },
            set: { selectedTask = $0 }
        )
    }

    private var compactCapturePresented: Binding<Bool> {
        Binding(
            get: { isRegularWidth ? false : capturePresented },
            set: { capturePresented = $0 }
        )
    }

    var body: some View {
        ZStack {
            // Liquid aurora canvas at the shell root (was a flat fill). Native
            // chrome (tab bar / split view) rides translucently over it so the
            // brand wallpaper reads through — the iOS half of the macOS identity.
            LiquidWallpaper()
            rootContent
            // Regular-width Quick Capture overlay sits at the window root (not the
            // detail pane) so its scrim dims the whole window — sidebar included —
            // mirroring the Mac full-window scrim. Self-gates on `isRegularWidth`.
            captureOverlay
        }
        .animation(DS.Motion.standard, value: capturePresented)
        // Nexus is a dark-only design. Force it at the shell root so EVERY tab —
        // not just Today and the iPad split — paints dark; otherwise, on a
        // light-mode device, unstyled system surfaces (segmented-control tracks,
        // navigation/grouped backgrounds, the Tasks filter strip) render light
        // and tear holes in the dark theme.
        .preferredColorScheme(.dark)
        .sheet(item: $customSnoozeTask) { task in
            CustomSnoozeSheet(task: task)
                .presentationDetents([.medium])
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if let task = activeFocusTask {
            FocusView(task: task)
        } else if let state = staleFocusState {
            tabShell
                .task(id: state.pinnedTaskID) { @MainActor in state.exit() }
        } else {
            tabShell
        }
    }

    @MainActor
    private var activeFocusTask: TaskItem? {
        guard
            let state = focusModeState,
            state.isInFocus,
            let id = state.pinnedTaskID
        else { return nil }
        return fetchPinnedTask(id: id)
    }

    private var staleFocusState: FocusModeState? {
        guard
            let state = focusModeState,
            state.isInFocus,
            state.pinnedTaskID != nil
        else { return nil }
        return state
    }

    private var tabShell: some View {
        Group {
            if isRegularWidth {
                regularShell
            } else {
                compactTabShell
            }
        }
        .task {
            await NotesComposition.bootstrap(openDailyNote: { openTodaysDailyNote() })
            guard let taskRepository else { return }
            await TasksComposition.bootstrap(
                repository: taskRepository,
                navigation: TaskCommandNavigation(
                    goToToday: { selectedTab = .today },
                    goToInbox: { selectedTab = .inbox },
                    openCapture: { openCaptureFromCommandPalette() },
                    selectedTask: { selectedTask }
                )
            )
        }
        .sheet(isPresented: $commandPalettePresented) {
            CommandPaletteView {
                commandPalettePresented = false
            }
            .padding(isRegularWidth ? 28 : 24)
            .presentationDetents(commandPaletteDetents)
            .presentationDragIndicator(isRegularWidth ? .hidden : .visible)
        }
        .sheet(isPresented: compactCapturePresented) {
            CaptureSheet(
                initialMode: captureMode,
                onSaved: { capturePresented = false },
                onCancelled: { capturePresented = false }
            )
            .presentationDetents(captureDetents)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $pencilCapturePresented) {
            NavigationStack {
                PencilCaptureView()
                    .navigationTitle("Pencil Capture")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents(captureDetents)
        }
        .sheet(item: compactSelectedTask) { task in
            NavigationStack {
                TaskDetailInspector(task: task)
                    .navigationTitle(task.title.isEmpty ? "Task" : task.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { selectedTask = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onReceive(NotificationCenter.default.publisher(for: .nexusGoToSettings)) { _ in
            selectedTab = .settings
        }
    }

    /// O4: pending-flag first, then switch to the Notes tab — same two-path
    /// delivery as macOS (`DailyNoteOpenRequest` doc).
    @MainActor
    private func openTodaysDailyNote() {
        DailyNoteOpenRequest.shared.request()
        selectedTab = .notes
    }

    private var compactTabShell: some View {
        TabView(selection: $selectedTab) {
            TodayTab(
                onOpenCapture: { openCapture(mode: $0) },
                onOpenCommandPalette: { commandPalettePresented = true },
                onOpenPencilCapture: { pencilCapturePresented = true },
                content: { liquidTodayMain }
            )
            .tag(NexusTab.today)
            .tabItem { Label("Today", systemImage: "circle.dotted") }
            InboxTab(
                onOpenItem: { openInboxItem($0) },
                onOpenCapture: { openCapture(mode: .task) },
                onOpenCommandPalette: { commandPalettePresented = true },
                onUnreadCountChanged: { inboxUnreadCount = $0 }
            )
            .tag(NexusTab.inbox)
            .tabItem { Label("Inbox", systemImage: "tray") }
            .badge(inboxUnreadCount)
            TasksTab(
                onOpenTask: { selectedTask = $0 },
                onOpenCapture: { openCapture(mode: .task) },
                onOpenCommandPalette: { commandPalettePresented = true }
            )
            .tag(NexusTab.tasks)
            .tabItem { Label("Tasks", systemImage: "checkmark.square") }
            ProjectsTab(
                onOpenCapture: { openCapture(mode: $0) },
                onOpenCommandPalette: { commandPalettePresented = true },
                content: { liquidProjectsMain }
            )
            .tag(NexusTab.projects)
            .tabItem { Label("Projects", systemImage: "square.stack.3d.up") }
            NotesListView()
                .tag(NexusTab.notes)
                .tabItem { Label("Notes", systemImage: "note.text") }
            AgentTab(viewModel: agentViewModel)
                .tag(NexusTab.agent)
                .tabItem { Label("Agent", systemImage: "sparkles") }
            calendarDetail
                .tag(NexusTab.calendar)
                .tabItem { Label("Calendar", systemImage: "calendar") }
            PeopleListView()
                .tag(NexusTab.people)
                .tabItem { Label("People", systemImage: "person.crop.circle") }
            if let meetingsComposition {
                iOSMeetingsHostResolver(composition: meetingsComposition)
                    .tag(NexusTab.meetings)
                    .tabItem { Label("Meetings", systemImage: "person.wave.2") }
            }
            SettingsTab(
                cloudKitEnabled: cloudKitEnabled,
                containerIdentifier: containerIdentifier,
                aiRouter: aiRouter,
                permissionState: permissionState,
                agentSettingsContext: agentSettingsContext,
                meetingsComposition: meetingsComposition,
                manageModelsContent: manageModelsContent,
                quietHoursStartTime: $quietHoursState.startTime,
                quietHoursEndTime: $quietHoursState.endTime,
                onExportRequested: onExportRequested
            )
            .tag(NexusTab.settings)
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // Linear spec: active tab indicator = Accent.lime (single primary accent).
        .tint(NexusColor.Accent.lime)
        .onAppear {
            resolveUnavailableTab()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            resolveUnavailableTab()
        }
    }

    @MainActor
    private func resolveUnavailableTab() {
        if selectedTab == .meetings && meetingsComposition == nil {
            selectedTab = .settings
        }
    }

    @MainActor
    private func fetchPinnedTask(id: UUID) -> TaskItem? {
        let openStatus = TaskStatus.open.rawValue
        let taskID = id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.id == taskID && task.deletedAt == nil && task.statusRaw == openStatus
            }
        )
        return try? modelContext.fetch(descriptor).first
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
    private func pickFocusCandidate() -> TaskItem? {
        let openStatus = TaskStatus.open.rawValue
        let highPriority = TaskPriority.high.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil && task.statusRaw == openStatus && task.isTemplate == false
            }
        )
        guard let tasks = try? modelContext.fetch(descriptor) else { return nil }
        return tasks.first { $0.pinnedAsFocus } ?? tasks.first { $0.priorityRaw == highPriority }
    }

    @MainActor
    private func openInboxItem(_ item: InboxItem) {
        let id = item.id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.id == id && task.deletedAt == nil
            }
        )
        selectedTask = try? modelContext.fetch(descriptor).first
    }

    private func openCapture(mode: CapturePane.Mode) {
        captureMode = mode
        capturePresented = true
    }

    @MainActor
    private func openCaptureFromCommandPalette() {
        commandPalettePresented = false
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(nanoseconds: 250_000_000)
            openCapture(mode: .task)
        }
    }
}

extension ContentView {
    fileprivate var regularShell: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(276, max(228, proxy.size.width * 0.27))
            HStack(spacing: 0) {
                regularSidebar
                    .frame(width: sidebarWidth)
                regularDetail
                    .frame(
                        width: max(0, proxy.size.width - sidebarWidth),
                        height: proxy.size.height
                    )
                    .overlay(alignment: .trailing) { taskPeek }
                    .animation(DS.Motion.standard, value: selectedTask?.id)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Lime is reserved for the nav rail's active indicator (set explicitly per
        // row below). Keep the shell tint neutral so it doesn't leak lime onto
        // incidental detail controls; Text.primary also suppresses the system blue
        // accent that an unset tint would fall back to.
        .tint(NexusColor.Text.primary)
        .preferredColorScheme(.dark)
        .onAppear {
            resolveUnavailableTab()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            resolveUnavailableTab()
        }
    }

    fileprivate var regularSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            regularSidebarBrand
            regularPrimaryActions
            regularNavigationRows
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // One continuous backdrop across the whole window (macOS parity): the
        // shell aurora flows behind BOTH columns, and the sidebar is only a faint
        // darkening scrim over that same canvas — not a separate material slab
        // that seams against the detail pane. A barely-there hairline hints the
        // split without cutting the window in two.
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NexusColor.Line.hairline.opacity(0.5))
                .frame(width: 1)
        }
    }

    fileprivate var regularSidebarBrand: some View {
        HStack(spacing: 10) {
            Text("N")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(NexusColor.Text.primary)
                .frame(width: 32, height: 32)
                .background(
                    NexusColor.Background.controlHover,
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Nexus")
                    .font(NexusType.body.weight(.semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                Text("Personal")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
        .padding(.bottom, 4)
    }

    fileprivate var regularPrimaryActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            NexusButton(
                variant: .primary,
                size: .lg,
                action: { openCapture(mode: .task) },
                label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("New Task")
                        Spacer(minLength: 0)
                    }
                }
            )
            .accessibilityLabel("Capture task")

            HStack(spacing: 8) {
                NexusButton(
                    variant: .default,
                    size: .md,
                    action: { commandPalettePresented = true },
                    label: {
                        HStack(spacing: 6) {
                            Image(systemName: "command")
                            Text("Commands")
                        }
                    }
                )
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityLabel("Open command palette")

                NexusButton(
                    variant: .default,
                    size: .md,
                    action: { pencilCapturePresented = true },
                    label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.tip")
                            Text("Pencil")
                        }
                    }
                )
                .accessibilityLabel("Pencil capture")
            }
        }
    }

    fileprivate var regularNavigationRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(regularNavigationItems, id: \.tab) { item in
                regularNavigationButton(item)
            }
        }
        .padding(.top, 6)
    }

    fileprivate func regularNavigationButton(_ item: RegularNavigationItem) -> some View {
        // Mac-parity sidebar row: the shared `LiquidSidebarNavRow` — a soft pill
        // highlight (white glass fill + hairline + faint accent glow) for the
        // selected module, no left accent bar (the old Linear rail idiom).
        LiquidSidebarNavRow(
            item.title,
            systemImage: item.systemImage,
            isSelected: selectedTab == item.tab,
            action: { selectedTab = item.tab }
        )
    }

    @ViewBuilder
    fileprivate var regularDetail: some View {
        switch selectedTab {
        case .today:
            liquidTodayMain
                .background(Color.clear)
        case .inbox:
            InboxTab(
                onOpenItem: { openInboxItem($0) },
                onOpenCapture: { openCapture(mode: .task) },
                onOpenCommandPalette: { commandPalettePresented = true },
                onUnreadCountChanged: { inboxUnreadCount = $0 },
                showsToolbarActions: false
            )
        case .tasks:
            TasksTab(
                onOpenTask: { selectedTask = $0 },
                onOpenCapture: { openCapture(mode: .task) },
                onOpenCommandPalette: { commandPalettePresented = true },
                showsToolbarActions: false
            )
        case .projects:
            liquidProjectsMain
                .background(Color.clear)
        case .notes:
            NotesListView()
        case .calendar:
            calendarDetail
        case .people:
            PeopleListView()
        case .agent:
            AgentTab(viewModel: agentViewModel)
        case .meetings:
            if let meetingsComposition {
                iOSMeetingsHostResolver(composition: meetingsComposition)
                    .background(Color.clear)
            } else {
                ContentUnavailableView("Meetings unavailable", systemImage: "person.wave.2")
                    .foregroundStyle(NexusColor.Text.secondary)
            }
        case .stats:
            ProductivityDashboardView()
                .background(Color.clear)
        case .settings:
            settingsTab
        }
    }

    @ViewBuilder
    fileprivate var calendarDetail: some View {
        if let calendarViewModel {
            CalendarView(viewModel: calendarViewModel)
        } else {
            Color.clear
                .onAppear {
                    #if canImport(EventKit) && !os(watchOS)
                    let provider = EventKitCalendarProvider.shared
                    calendarViewModel = CalendarViewModel(
                        context: modelContext,
                        reader: provider,
                        writer: provider,
                        listing: provider,
                        changes: provider
                    )
                    #endif
                }
        }
    }

    fileprivate var settingsTab: some View {
        SettingsTab(
            cloudKitEnabled: cloudKitEnabled,
            containerIdentifier: containerIdentifier,
            aiRouter: aiRouter,
            permissionState: permissionState,
            agentSettingsContext: agentSettingsContext,
            meetingsComposition: meetingsComposition,
            manageModelsContent: manageModelsContent,
            quietHoursStartTime: $quietHoursState.startTime,
            quietHoursEndTime: $quietHoursState.endTime,
            onExportRequested: onExportRequested
        )
    }

    fileprivate var regularNavigationItems: [RegularNavigationItem] {
        var items: [RegularNavigationItem] = [
            RegularNavigationItem(tab: .today, title: "Today", systemImage: "circle.dotted"),
            RegularNavigationItem(tab: .inbox, title: "Inbox", systemImage: "tray"),
            RegularNavigationItem(tab: .tasks, title: "Tasks", systemImage: "checkmark.square"),
            RegularNavigationItem(tab: .projects, title: "Projects", systemImage: "square.stack.3d.up"),
            RegularNavigationItem(tab: .notes, title: "Notes", systemImage: "note.text"),
            RegularNavigationItem(tab: .calendar, title: "Calendar", systemImage: "calendar"),
            RegularNavigationItem(tab: .people, title: "People", systemImage: "person.crop.circle"),
            RegularNavigationItem(tab: .agent, title: "Agent", systemImage: "sparkles"),
        ]
        if meetingsComposition != nil {
            items.append(
                RegularNavigationItem(tab: .meetings, title: "Meetings", systemImage: "person.wave.2")
            )
        }
        // Stats is an analytics surface: a sidebar row on iPad (parity with the
        // macOS ⌘6 destination). iPhone keeps it as a Settings link (no tab).
        items.append(RegularNavigationItem(tab: .stats, title: "Stats", systemImage: "chart.bar"))
        items.append(RegularNavigationItem(tab: .settings, title: "Settings", systemImage: "gearshape"))
        return items
    }

    fileprivate var commandPaletteDetents: Set<PresentationDetent> {
        isRegularWidth ? [.height(560)] : [.medium]
    }

    fileprivate var captureDetents: Set<PresentationDetent> {
        isRegularWidth ? [.height(620), .large] : [.medium, .large]
    }
}

private struct RegularNavigationItem: Hashable {
    let tab: ContentView.NexusTab
    let title: String
    let systemImage: String
}

// MARK: - Liquid Today (ported from macOS)
//
// Mirrors `Apps/NexusMac/ContentView+LiquidToday.swift`: the Today card
// composition (`LiquidTodayScreen`, reflowing per size class) is mounted on iOS
// too, with cross-module content (daily brief, meeting intel, focus gaps)
// composed here as plain values. Lives in this file because `NexusTab` /
// `selectedTab` are fileprivate to it.
extension ContentView {

    /// The ported Liquid Today screen — one column on iPhone, grid + inspector
    /// on iPad — shared by the compact tab and the regular split detail.
    var liquidTodayMain: some View {
        LiquidTodayScreen(
            model: liquidTodayModel,
            meetingIntelProvider: { fetchTodayMeetingIntel() },
            briefProvider: dailyBriefProvider,
            focusGapProvider: { events, window in
                SchedulingIntelligence.suggestedFocusBlocks(events: events, within: window)
            },
            onNavigate: { navigateToday($0) },
            onOpenTask: { selectedTask = $0 },
            onOpenCapture: { openCapture(mode: $0) }
        )
    }

    /// Routes the Today cards' navigation intents to the iOS tab switch. Projects
    /// is now a dedicated tab (compact + iPad sidebar). Stats is an iPad sidebar
    /// destination only — on compact iPhone it has no tab, so route it to Tasks.
    func navigateToday(_ selection: TodayNavSelection) {
        switch selection {
        case .today: selectedTab = .today
        case .inbox: selectedTab = .inbox
        case .meetings: selectedTab = .meetings
        case .tasks: selectedTab = .tasks
        case .projects: selectedTab = .projects
        case .stats: selectedTab = isRegularWidth ? .stats : .tasks
        case .notes: selectedTab = .notes
        case .calendar: selectedTab = .calendar
        case .people: selectedTab = .people
        case .agent: selectedTab = .agent
        case .settings: selectedTab = .settings
        }
    }

    /// The shared Liquid Projects screen — mounted by the compact `ProjectsTab`
    /// and the iPad regular-split detail. Opening a card/row routes through the
    /// same `selectedTask` seam as the rest of the shell (inspector ⊥ Agent
    /// invariant preserved). Defined here because `NexusTab` is fileprivate.
    var liquidProjectsMain: some View {
        LiquidProjectScreen(
            model: liquidProjectsModel,
            onOpenTask: { selectedTask = $0 }
        )
        // Pin structural identity so detail-branch re-evaluations never tear down
        // the screen's internal @State (selected project, tab, picker mode).
        .id(NexusTab.projects)
    }

    /// Adapts the shared `AgentBriefService` seam to the Liquid screen's
    /// value-typed provider; `nil` → the Daily Brief card shows its empty state.
    private var dailyBriefProvider: LiquidTodayBriefProvider? {
        guard agentEnabled, let agentBriefService else { return nil }
        return { input in
            await agentBriefService.brief(
                for: AgentBriefRequest(
                    counts: AgentBriefCounts(
                        overdue: input.overdue,
                        today: input.today,
                        noDate: input.noDate,
                        awaiting: input.awaiting
                    ),
                    firstTitles: input.firstTitles,
                    now: input.now
                )
            )
        }
    }

    /// Most recent processed meeting as a plain value for the Meeting
    /// Intelligence card (mirrors the macOS seam).
    @MainActor
    private func fetchTodayMeetingIntel() -> LiquidTodayMeetingIntel? {
        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.deletedAt == nil && $0.processedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let meeting = try? modelContext.fetch(descriptor).first else { return nil }
        let status = MeetingProcessingStatus(rawValue: meeting.processingStatus)
        let decisions = MeetingSummarySections.parse(summaryText: meeting.summaryText).decisions
        return LiquidTodayMeetingIntel(
            title: meeting.title,
            occurredAt: meeting.startedAt,
            durationSec: meeting.durationSec,
            summary: meeting.summaryText,
            decisions: Array(decisions.prefix(3)),
            actionItemCount: meeting.actionItemIDs.count,
            statusLabel: status == .ready ? "Processed" : (status == .failed ? "Failed" : "Processing")
        )
    }
}

#Preview {
    ContentView(
        cloudKitEnabled: false,
        containerIdentifier: "iCloud.com.kacperpietrzyk.Nexus",
        permissionState: NotificationPermissionState(),
        agentSettingsContext: nil,
        manageModelsContent: nil,
        onExportRequested: {}
    )
    .modelContainer(for: [TaskItem.self], inMemory: true)
}
