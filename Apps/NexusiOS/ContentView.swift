import CommandPaletteShell
import InboxShell
import NexusAI
import NexusAgent
import NexusCore
import NexusMeetings
import NexusUI
import NotesFeature
import SwiftData
import SwiftUI
import TasksFeature
import UIKit

// The iOS root shell mounts one tab/destination per feature
// (Today/Inbox/Tasks/Notes/Agent/Meetings/Settings) in both the compact tab bar
// and the regular-width split; it grows by a tab + a `regularDetail` case + a
// nav item per feature by design — the same structural per-feature growth that
// disables `file_length` on `NexusiOSApp`. The Notes mount crossed 600 lines.
// swiftlint:disable file_length
struct ContentView: View {

    fileprivate enum NexusTab: Hashable {
        case today, inbox, tasks, notes, meetings, agent, settings
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

    @State private var selectedTab: NexusTab = .today
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
            NexusColor.Background.base.ignoresSafeArea()
            rootContent
            // Regular-width Quick Capture overlay sits at the window root (not the
            // detail pane) so its scrim dims the whole window — sidebar included —
            // mirroring the Mac full-window scrim. Self-gates on `isRegularWidth`.
            captureOverlay
        }
        .animation(NexusMotion.standard, value: capturePresented)
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

    private var compactTabShell: some View {
        TabView(selection: $selectedTab) {
            TodayTab(
                onOpenTask: { selectedTask = $0 },
                onOpenCapture: { openCapture(mode: $0) },
                onOpenCommandPalette: { commandPalettePresented = true },
                onOpenAgent: { selectedTab = .agent },
                onOpenPencilCapture: { pencilCapturePresented = true }
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
            NotesListView()
                .tag(NexusTab.notes)
                .tabItem { Label("Notes", systemImage: "note.text") }
            AgentTab(viewModel: agentViewModel)
                .tag(NexusTab.agent)
                .tabItem { Label("Agent", systemImage: "sparkles") }
            if horizontalSizeClass == .regular, let meetingsComposition {
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
        if selectedTab == .meetings && horizontalSizeClass != .regular {
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
                task.deletedAt == nil && task.statusRaw == openStatus
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
                    .animation(NexusMotion.standard, value: selectedTask?.id)
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
        .background(NexusColor.Background.panel)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NexusColor.Line.hairline)
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
        Button {
            selectedTab = item.tab
        } label: {
            HStack(spacing: 0) {
                // Lime left-bar indicator for active item (Linear nav rail idiom).
                Rectangle()
                    .fill(selectedTab == item.tab ? NexusColor.Accent.lime : Color.clear)
                    .frame(width: 2)
                    .cornerRadius(1)

                HStack(spacing: 9) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            selectedTab == item.tab ? NexusColor.Accent.lime : NexusColor.Text.tertiary
                        )
                        .frame(width: 20)

                    Text(item.title)
                        .nexusType(.bodySmall)
                        .foregroundStyle(
                            selectedTab == item.tab ? NexusColor.Text.primary : NexusColor.Text.secondary
                        )

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selectedTab == item.tab {
                    RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                        .fill(NexusColor.Background.controlHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    @ViewBuilder
    fileprivate var regularDetail: some View {
        switch selectedTab {
        case .today:
            TodayDashboard(
                showsNavigationRail: false,
                onOpenTask: { selectedTask = $0 },
                onOpenCapture: { openCapture(mode: $0) },
                onOpenCommandPalette: { commandPalettePresented = true },
                onOpenAgent: { selectedTab = .agent },
                forceCompactLayout: true,
                showsCompactCaptureFAB: false
            )
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
        case .notes:
            NotesListView()
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
        case .settings:
            settingsTab
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
            RegularNavigationItem(tab: .notes, title: "Notes", systemImage: "note.text"),
            RegularNavigationItem(tab: .agent, title: "Agent", systemImage: "sparkles"),
        ]
        if meetingsComposition != nil {
            items.append(
                RegularNavigationItem(tab: .meetings, title: "Meetings", systemImage: "person.wave.2")
            )
        }
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
