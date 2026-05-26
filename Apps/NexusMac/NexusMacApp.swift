import CommandPaletteShell
import InboxShell
import NexusAI
import NexusAgent
import NexusAgentTools
import NexusAgentToolsExtras
import NexusCore
import NexusMeetings
import NexusSearch
import NexusSync
import NexusUI
import SwiftData
import SwiftUI
import TasksFeature
import UserNotifications

// The Mac composition root wires every subsystem (model container, AI graph,
// agent XPC, meetings, scheduler, welcome flow). It grows by ~1 stored prop +
// init line per feature by design; file_length is disabled for the same
// structural reason as the type_body_length disable below (cf. AgentInputBar).
// swiftlint:disable file_length

@main
// swiftlint:disable:next type_body_length
struct NexusMacApp: App {
    @NSApplicationDelegateAdaptor(NexusMacAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var scheduler: Scheduler
    @State private var exportPickerPresented = false
    @State private var lastExportResult: MarkdownExportResult?
    @State private var permissionState = NotificationPermissionState()
    @State private var quietHoursState = QuietHoursViewState()
    @State private var agentListenerActive: Bool
    @State private var focusModeState = FocusModeState()
    @AppStorage(NexusPreferences.Keys.welcomeShown) private var welcomeShown: Bool = false
    private let container: ModelContainer
    private let environment: NexusEnvironment
    private let search: SearchSubsystem
    private let aiRouter: AIRouter
    // Strong ref — owns the MLX lifecycle + memory guard; dropping it silently disables unload-on-pressure.
    private let aiGraph: AIComposition.AIGraph
    private let taskParser: CompositeNLParser
    private let taskRepository: TaskItemRepository
    private let notificationScheduler: NotificationScheduler
    private let captureController: CaptureWindowController
    // Strong ref — UNUserNotificationCenter does NOT retain its delegate.
    private let actionHandler: NotificationActionHandler
    private let agentActivityLog: AgentActivityLog
    private let agentComposition: AgentComposition
    private let meetingsComposition: MeetingsComposition
    private let meetingNavigationRouter: MeetingNavigationRouter
    private let meetingsHelperXPCClient: MeetingsHelperXPCClient
    private let helperToastBridge: HelperToastBridge
    private let agentXPCListener: NSXPCListener
    private let agentXPCService: NexusAgentXPCService
    // Retained for the process lifetime — its kicked-off MLX downloads
    // (multi-GB) must outlive the welcome sheet.
    private let welcomeMLXDownloads: WelcomeMLXDownloadCoordinator

    // The composition root's init grows by ~1 wiring line per feature by
    // design — same structural rationale as the file_length / type_body_length
    // disables above (the MLX preload + rebind wiring added the lines that
    // crossed the threshold).
    // swiftlint:disable:next function_body_length
    init() {
        NexusPreferences.migrateLegacyAgentPreloadSpeechKey()
        NexusPreferences.purgeLegacyAgentSidebarOpenKey()
        UserDefaultsQuietHoursStore.migrateFromStandardIfNeeded()
        NexusFontRegistration.registerAll()
        if UserDefaultsHelperAutoRecordStore.shared.isEnabled() { MeetingsHelperSMAppServiceManager.registerIfNeeded() }
        let env = NexusEnvironment.current
        let made = Self.makeModelContainer(environment: env)
        self.environment = env
        self.container = made
        self.search = SearchSubsystem.makeLive()
        self.aiGraph = AIComposition.makeGraph(container: made)
        self.aiRouter = self.aiGraph.router
        Self.preloadWhisperKitIfRequested(router: self.aiRouter)
        Self.preloadMLXIfRequested(router: self.aiRouter, lifecycle: self.aiGraph.mlxLifecycle)
        self.taskParser = TasksComposition.makeParser(router: self.aiRouter)
        let notifScheduler = TasksComposition.makeNotificationScheduler()
        self.notificationScheduler = notifScheduler
        self.taskRepository = TasksComposition.makeRepository(
            for: made.mainContext,
            notifications: NotificationSchedulingAdapter(scheduler: notifScheduler)
        )
        self.meetingsComposition = Self.makeMeetingsComposition(
            context: made.mainContext,
            router: self.aiRouter,
            taskRepository: self.taskRepository
        )
        let meetingNavigation = Self.makeMeetingNavigationInfrastructure()
        self.meetingsHelperXPCClient = meetingNavigation.xpcClient
        self.meetingNavigationRouter = meetingNavigation.router
        self.helperToastBridge = meetingNavigation.bridge
        let heroBriefService = HeroBriefService(router: self.aiRouter)
        TaskIntentRuntime.configure(parser: self.taskParser, repository: self.taskRepository)
        self.captureController = CaptureWindowController(parser: self.taskParser, repository: self.taskRepository)
        self.agentComposition = Self.makeAgentComposition(
            modelContext: made.mainContext,
            router: self.aiRouter,
            searchIndex: self.search.searchIndex,
            taskRepository: self.taskRepository,
            nlParser: self.taskParser,
            heroBriefService: heroBriefService,
            meetingTools: self.meetingsComposition.agentTools(),
            ocrPipeline: self.aiGraph.ocrPipeline
        )
        let handler = Self.installNotificationHandler(repository: self.taskRepository, scheduler: notifScheduler)
        self.actionHandler = handler
        let agentInfrastructure = Self.makeAgentInfrastructure(
            modelContext: made.mainContext,
            taskRepository: self.taskRepository,
            searchIndex: self.search.searchIndex,
            nlParser: self.taskParser,
            heroBriefService: heroBriefService,
            agentComposition: self.agentComposition
        )
        self.agentActivityLog = agentInfrastructure.activityLog
        self.agentXPCService = agentInfrastructure.service
        self.agentXPCListener = agentInfrastructure.listener
        self._agentListenerActive = State(initialValue: agentInfrastructure.listenerActive)
        self._scheduler = State(initialValue: Scheduler())
        let router = self.aiRouter
        self.welcomeMLXDownloads = WelcomeMLXDownloadCoordinator(
            onChatAssigned: { try? await router.reloadMLXChat() },
            onEmbedderAssigned: { try? await router.reloadMLXEmbedder() }
        )

        Self.rebuildSearchIndex(context: made.mainContext, index: self.search.searchIndex)
    }

    private static func preloadWhisperKitIfRequested(router: AIRouter) {
        guard UserDefaults.standard.bool(forKey: NexusPreferences.Keys.agentVoicePreloadWhisperKit) else {
            return
        }

        _Concurrency.Task.detached(priority: .utility) {
            try? await router.preloadWhisperKit()
        }
    }

    /// Warms the on-device MLX provider(s) at launch, breaking the
    /// availability/load cycle so a cold MLX provider can ever be selected.
    ///
    /// - Chat: preloads ONLY when the (previously dead) `mlxPreloadChat`
    ///   toggle is on AND a real chat assignment exists AND its folder is on
    ///   disk. The folder is resolved through the SAME `lifecycle` the engine
    ///   will resolve at load time, so the existence check matches what the
    ///   engine sees — never an attempt to load the `unknown` fallback.
    /// - Embedder: preloaded whenever a real embedder assignment exists and
    ///   its folder is on disk — NO toggle (search/RAG depends on it; the
    ///   asymmetry vs chat is intentional).
    private static func preloadMLXIfRequested(
        router: AIRouter,
        lifecycle: MLXLifecycleController
    ) {
        let store = ModelManifestLocalState.Store()
        let fileManager = FileManager.default

        let chatToggleOn = UserDefaults.standard.bool(
            forKey: NexusPreferences.Keys.mlxPreloadChat)
        let chatReady =
            store.currentChatAssignment() != nil
            && fileManager.fileExists(atPath: lifecycle.chatFolderURL().path)
        if chatToggleOn && chatReady {
            _Concurrency.Task.detached(priority: .utility) {
                try? await router.preloadMLXChat()
            }
        }

        let embedderReady =
            store.currentEmbedderAssignment() != nil
            && fileManager.fileExists(atPath: lifecycle.embedderFolderURL().path)
        if embedderReady {
            _Concurrency.Task.detached(priority: .utility) {
                try? await router.preloadMLXEmbedder()
            }
        }
    }

    var body: some Scene {
        Window("Nexus", id: "main") {
            ContentView()
                .environment(\.searchSubsystem, search)
                .environment(\.aiRouter, aiRouter)
                .environment(\.taskParser, taskParser)
                .environment(\.taskRepository, taskRepository)
                .environment(\.notificationScheduler, notificationScheduler)
                .environment(\.agentActivityLog, agentActivityLog)
                .environment(\.agentChatViewModel, agentComposition.chatViewModel)
                .environment(\.agentBriefService, agentComposition.briefService)
                .environment(\.meetingsComposition, meetingsComposition)
                .environment(\.meetingNavigationRouter, meetingNavigationRouter)
                .environment(\.focusModeState, focusModeState)
                #if canImport(EventKit) && !os(watchOS)
            .environment(\.calendarEventProvider, EventKitCalendarProvider.shared)
                #endif
                // Cheap insurance for non-dashboard states (Focus mode, future
                // sheets) where `NexusWallpaper` is not painted; wallpaper-bearing
                // dashboard ignores safe area and covers this anyway.
                .containerBackground(NexusColor.Background.base, for: .window)
                .background {
                    ExportFolderPicker(isPresented: $exportPickerPresented) { folder in
                        _Concurrency.Task {
                            do {
                                let result = try await MarkdownExporter.export(
                                    container: container,
                                    types: TaskItem.self,
                                    to: folder
                                )
                                lastExportResult = result
                            } catch {
                                // Phase 0f: surface via OSLog when logger lands in Phase 1.
                            }
                        }
                    }
                }
                .task { await bootstrapScheduler() }
                .task { await agentComposition.scheduler.start() }
                .task {
                    await NotificationCategories.registerAll(on: SystemNotificationCenter())
                    await permissionState.refresh()
                    await permissionState.requestIfNeeded()
                }
                .task {
                    if scenePhase == .active {
                        agentComposition.runActiveMaintenance(context: container.mainContext)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    agentComposition.runActiveMaintenance(context: container.mainContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    syncAgentListener(
                        enabled: UserDefaults.standard.bool(forKey: AgentServiceConstants.mcpEnabledKey)
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .nexusOpenCapture)) { notification in
                    let mode = notification.object as? CapturePane.Mode ?? .task
                    captureController.show(mode: mode)
                }
                .sheet(
                    isPresented: Binding(
                        get: { !welcomeShown },
                        set: { if !$0 { welcomeShown = true } }
                    )
                ) {
                    WelcomeFlowView(
                        onFinished: { welcomeShown = true },
                        extraScreens: welcomeMLXDownloads.extraScreens(
                            followedBy: [
                                { advance in AnyView(MeetingsWelcomeStep { _ in advance() }) }
                            ]
                        )
                    )
                    .frame(minWidth: 640, minHeight: 520)
                    .interactiveDismissDisabled(true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task…") {
                    NotificationCenter.default.post(name: .nexusOpenCapture, object: CapturePane.Mode.task)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("Navigate") {
                Button("Go to Today") {
                    NotificationCenter.default.post(name: .nexusGoToToday, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Go to Inbox") {
                    NotificationCenter.default.post(name: .nexusGoToInbox, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Go to Meetings") {
                    NotificationCenter.default.post(name: .nexusGoToMeetings, object: nil)
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Go to Tasks") {
                    NotificationCenter.default.post(name: .nexusGoToTasks, object: nil)
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("Go to Agent") {
                    NotificationCenter.default.post(name: .nexusToggleAgentSidebar, object: nil)
                }
                .keyboardShortcut("5", modifiers: [.command])

                Button("Go to Stats") {
                    NotificationCenter.default.post(name: .nexusGoToStats, object: nil)
                }
                .keyboardShortcut("6", modifiers: [.command])

                Button("Go to Settings") {
                    NotificationCenter.default.post(name: .nexusGoToSettings, object: nil)
                }
                .keyboardShortcut("7", modifiers: [.command])
            }

            CommandMenu("Tasks") {
                Button("Quick Capture Panel…") {
                    captureController.toggle(mode: .task)
                }
                .keyboardShortcut("n", modifiers: [.command, .control])

                Divider()

                Button("Complete Selected Task") {
                    NotificationCenter.default.post(name: .nexusCompleteSelectedTask, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Snooze Selected Task 1 Hour") {
                    NotificationCenter.default.post(name: .nexusSnoozeSelectedTask, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Toggle Selected Task Focus") {
                    NotificationCenter.default.post(name: .nexusToggleSelectedTaskFocus, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }

            CommandMenu("Command") {
                Button("Open Command Palette…") {
                    NotificationCenter.default.post(name: .nexusOpenCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Ask Nexus") {
                    NotificationCenter.default.post(name: .nexusToggleAgentSidebar, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            CommandMenu("Focus") {
                Button("Toggle Focus") {
                    focusModeState.toggle(pickFrom: { resolveFocusCandidate() })
                }
                .keyboardShortcut(".", modifiers: .command)
            }
        }

        Settings {
            NavigationStack {
                NexusSettingsView(
                    cloudKitEnabled: environment.cloudKitEnabled,
                    containerIdentifier: environment.cloudKitContainerIdentifier,
                    aiRouter: aiRouter,
                    notificationsAuthorized: permissionState.status != .denied,
                    quietHoursStartTime: $quietHoursState.startTime,
                    quietHoursEndTime: $quietHoursState.endTime,
                    externalAccessConfig: NexusSettingsView.ExternalAccessConfig(
                        sidecarPath: Bundle.main.bundleURL
                            .appendingPathComponent("Contents/MacOS/nexus-mcp")
                            .path,
                        activityLog: agentActivityLog
                    ),
                    agentSettingsContent: AnyView(
                        AgentSettingsView(context: agentComposition.settingsContext)
                    ),
                    meetingsSettingsContent: AnyView(
                        MeetingsSettingsSection(
                            composition: meetingsComposition,
                            helperViewModel: MeetingsHelperSettingsViewModel()
                        )
                    ),
                    manageModelsContent: AnyView(
                        ManageModelsSection(
                            localStateStore: ModelManifestLocalState.Store(),
                            downloadManager: welcomeMLXDownloads.manager,
                            lifecycle: aiGraph.mlxLifecycle,
                            onChatReassigned: { [aiRouter] in try? await aiRouter.reloadMLXChat() },
                            onEmbedderReassigned: { [aiRouter] in
                                try? await aiRouter.reloadMLXEmbedder()
                            }
                        )
                    ),
                    onExportRequested: { exportPickerPresented = true }
                )
                .navigationTitle("Settings")
            }
            // MP-4.1 §3: native Toggle/DatePicker/Button controls in the
            // Settings Form inherit this scene tint — burning it
            // achromatic is what makes the whole Form render without
            // accent hue. `Text.primary` matches the oracle
            // `SettingsPreview.toggle(_:)` "on"-knob fill (§2
            // LabPalette.ink).
            .tint(NexusColor.Text.primary)
            .task { await permissionState.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                syncAgentListener(
                    enabled: UserDefaults.standard.bool(forKey: AgentServiceConstants.mcpEnabledKey)
                )
            }
        }

        MenuBarExtra("Nexus", systemImage: "checklist") {
            NexusMenuBarContent(
                openCapture: { captureController.toggle(mode: .task) }
            )
        }
        .menuBarExtraStyle(.menu)
    }

    /// Mac path: register `.tombstonePurge`, run once on launch, then drive `runDue` every hour
    /// while the app is foreground. NSBackgroundActivityScheduler integration deferred (decision F2).
    private func bootstrapScheduler() async {
        let job = TombstonePurgeJob.make(container: container, linkableTypes: [TaskItem.self])
        await scheduler.register(job)
        await scheduler.runDue()
        // Foreground tick — Timer is fine for a single-job, single-window app.
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            _Concurrency.Task { await scheduler.runDue() }
        }
    }

    private func syncAgentListener(enabled: Bool) {
        if enabled, !agentListenerActive {
            agentXPCListener.resume()
            agentListenerActive = true
        } else if !enabled, agentListenerActive {
            agentXPCListener.suspend()
            agentListenerActive = false
        }
    }

    @MainActor
    private func resolveFocusCandidate() -> UUID? {
        let context = container.mainContext
        let openStatus = TaskStatus.open.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { item in
                item.deletedAt == nil && item.statusRaw == openStatus
            },
            sortBy: [
                SortDescriptor(\.dueAt, order: .forward),
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.title, order: .forward),
            ]
        )
        guard let items = try? context.fetch(descriptor) else { return nil }
        if let pinned = items.first(where: { $0.pinnedAsFocus }) { return pinned.id }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return items.first { item in
            guard item.priority == .high, let due = item.dueAt else { return false }
            return due >= startOfDay && due < startOfTomorrow
        }?.id
    }

    private static func installNotificationHandler(
        repository: TaskItemRepository,
        scheduler: NotificationScheduler
    ) -> NotificationActionHandler {
        let handler = NotificationActionHandler(repository: repository, scheduler: scheduler)
        UNUserNotificationCenter.current().delegate = handler
        return handler
    }

    private static func rebuildSearchIndex(context: ModelContext, index: SearchIndex) {
        // Rebuild the index from the live store on launch. D-0d-7: index is reproducible.
        _Concurrency.Task { @MainActor in
            do {
                try await index.rebuild(from: context, types: TaskItem.self)
            } catch {
                print("SearchIndex.rebuild failed on launch: \(error)")
            }
        }
    }

    private static func makeModelContainer(environment: NexusEnvironment) -> ModelContainer {
        do {
            try NexusModelContainer.migrateDefaultStoreToAppGroupIfNeeded()
            return try NexusModelContainer.make(
                environment: environment,
                groupContainerIdentifier: NexusModelContainer.appGroupIdentifier,
                extraModels: MeetingsComposition.extraModels,
                localOnlyExtraModels: MeetingsComposition.localOnlyExtraModels
            )
        } catch {
            fatalError("Failed to make NexusModelContainer: \(error)")
        }
    }

    private static func makeMeetingsComposition(
        context: ModelContext,
        router: AIRouter,
        taskRepository: TaskItemRepository
    ) -> MeetingsComposition {
        do {
            let composition = try MeetingsComposition(
                context: context,
                router: router,
                rootAudioFolder: meetingsRootFolder(),
                calendarProvider: EventKitCalendarProvider.shared,
                taskRepository: taskRepository
            )
            composition.registerInboxSource()
            return composition
        } catch {
            fatalError("Failed to compose Nexus Meetings: \(error)")
        }
    }

    private static func makeMeetingNavigationInfrastructure() -> MeetingNavigationInfrastructure {
        let xpcClient = MeetingsHelperXPCClient()
        let router = MeetingNavigationRouter()
        let bridge = HelperToastBridge(xpcClient: xpcClient, router: router)
        bridge.start()
        return MeetingNavigationInfrastructure(
            xpcClient: xpcClient,
            router: router,
            bridge: bridge
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func makeAgentInfrastructure(
        modelContext: ModelContext,
        taskRepository: TaskItemRepository,
        searchIndex: SearchIndex,
        nlParser: CompositeNLParser,
        heroBriefService: HeroBriefService,
        agentComposition: AgentComposition
    ) -> AgentInfrastructure {
        let log = AgentActivityLog()
        let agentContext = AgentToolBootstrap.makeContext(
            modelContext: modelContext,
            taskRepository: taskRepository,
            searchIndex: searchIndex,
            nlParser: nlParser,
            heroBriefService: heroBriefService
        )
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let service = NexusAgentXPCService(
            registry: agentComposition.toolRegistry,
            context: agentContext,
            activityLog: log,
            appVersion: appVersion,
            isEnabled: { UserDefaults.standard.bool(forKey: AgentServiceConstants.mcpEnabledKey) }
        )
        let listener = NSXPCListener(machServiceName: machServiceName())
        listener.delegate = service
        if UserDefaults.standard.bool(forKey: AgentServiceConstants.mcpEnabledKey) {
            listener.resume()
        }
        return AgentInfrastructure(
            activityLog: log,
            service: service,
            listener: listener,
            listenerActive: UserDefaults.standard.bool(forKey: AgentServiceConstants.mcpEnabledKey)
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func makeAgentComposition(
        modelContext: ModelContext,
        router: AIRouter,
        searchIndex: SearchIndex,
        taskRepository: TaskItemRepository,
        nlParser: CompositeNLParser,
        heroBriefService: HeroBriefService,
        meetingTools: [any AgentTool],
        ocrPipeline: OCRPipeline
    ) -> AgentComposition {
        let additionalTools = NexusAgentToolsExtras.tools() + meetingTools
        let agentContext = AgentToolBootstrap.makeContext(
            modelContext: modelContext,
            taskRepository: taskRepository,
            searchIndex: searchIndex,
            nlParser: nlParser,
            heroBriefService: heroBriefService
        )
        do {
            return try AgentComposition.make(
                platform: .mac,
                context: modelContext,
                router: router,
                searchIndex: searchIndex,
                taskRepository: taskRepository,
                aiLiveData: AISettingsLiveData(router: router),
                agentContext: agentContext,
                additionalTools: additionalTools,
                ocrPipeline: ocrPipeline,
                legacyBrief: makeLegacyBrief(using: heroBriefService)
            )
        } catch {
            fatalError("Failed to compose Nexus Agent: \(error)")
        }
    }

    private static func makeLegacyBrief(
        using service: HeroBriefService
    ) -> @Sendable (AgentBriefRequest) async -> String {
        { request in
            await service.brief(
                for: HeroBriefService.Counts(
                    overdue: request.counts.overdue,
                    today: request.counts.today,
                    noDate: request.counts.noDate,
                    awaiting: request.counts.awaiting
                ),
                firstTitles: request.firstTitles,
                now: request.now
            )
        }
    }

    private static func meetingsRootFolder() -> URL {
        MeetingAudioRootResolver.rootFolder()
    }
}

private struct AgentInfrastructure {
    let activityLog: AgentActivityLog
    let service: NexusAgentXPCService
    let listener: NSXPCListener
    let listenerActive: Bool
}

private struct MeetingNavigationInfrastructure {
    let xpcClient: MeetingsHelperXPCClient
    let router: MeetingNavigationRouter
    let bridge: HelperToastBridge
}

private struct SearchSubsystemKey: EnvironmentKey {
    static let defaultValue: SearchSubsystem? = nil
}

extension EnvironmentValues {
    var searchSubsystem: SearchSubsystem? {
        get { self[SearchSubsystemKey.self] }
        set { self[SearchSubsystemKey.self] = newValue }
    }
}

private struct AgentActivityLogKey: EnvironmentKey {
    static let defaultValue: AgentActivityLog? = nil
}

extension EnvironmentValues {
    var agentActivityLog: AgentActivityLog? {
        get { self[AgentActivityLogKey.self] }
        set { self[AgentActivityLogKey.self] = newValue }
    }
}

private struct MeetingsCompositionKey: EnvironmentKey {
    static let defaultValue: MeetingsComposition? = nil
}

private struct MeetingNavigationRouterKey: EnvironmentKey {
    static let defaultValue: MeetingNavigationRouter? = nil
}

extension EnvironmentValues {
    var meetingsComposition: MeetingsComposition? {
        get { self[MeetingsCompositionKey.self] }
        set { self[MeetingsCompositionKey.self] = newValue }
    }

    var meetingNavigationRouter: MeetingNavigationRouter? {
        get { self[MeetingNavigationRouterKey.self] }
        set { self[MeetingNavigationRouterKey.self] = newValue }
    }
}

extension Notification.Name {
    static let nexusGoToToday = Notification.Name("nexus.goToToday")
    static let nexusGoToInbox = Notification.Name("nexus.goToInbox")
    static let nexusGoToMeetings = Notification.Name("nexus.goToMeetings")
    static let nexusGoToTasks = Notification.Name("nexus.goToTasks")
    static let nexusGoToStats = Notification.Name("nexus.goToStats")
    static let nexusOpenCommandPalette = Notification.Name("nexus.openCommandPalette")
    static let nexusOpenCapture = Notification.Name("nexus.openCapture")
    static let nexusToggleAgentSidebar = Notification.Name("nexus.toggleAgentSidebar")
    static let nexusCompleteSelectedTask = Notification.Name("nexus.completeSelectedTask")
    static let nexusSnoozeSelectedTask = Notification.Name("nexus.snoozeSelectedTask")
    static let nexusToggleSelectedTaskFocus = Notification.Name("nexus.toggleSelectedTaskFocus")
}

/// Keeps the app alive when the main window is closed and reopens it on Dock click.
final class NexusMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            for window in sender.windows where window.identifier?.rawValue == "main" {
                window.makeKeyAndOrderFront(nil)
                return false
            }
        }
        return true
    }
}

private struct NexusMenuBarContent: View {
    let openCapture: () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Task…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .nexusOpenCapture, object: CapturePane.Mode.task)
            }
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button("Quick Capture Panel…") {
            openCapture()
        }
        .keyboardShortcut("n", modifiers: [.command, .control])

        Button("Command Palette…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .nexusOpenCommandPalette, object: nil)
            }
        }
        .keyboardShortcut("k", modifiers: [.command])

        Button("Open Nexus") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit Nexus") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
