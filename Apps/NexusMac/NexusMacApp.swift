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
import NotesFeature
import PeopleFeature
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
    private let noteRepository: NoteRepository
    private let personRepository: PersonRepository
    private let notificationScheduler: NotificationScheduler
    // Strong ref — UNUserNotificationCenter does NOT retain its delegate.
    private let actionHandler: NotificationActionHandler
    private let agentActivityLog: AgentActivityLog
    private let agentComposition: AgentComposition
    private let meetingsComposition: MeetingsComposition
    private let meetingNavigationRouter: MeetingNavigationRouter
    private let meetingsHelperXPCClient: MeetingsHelperXPCClient
    private let helperToastBridge: HelperToastBridge
    private let agentSocketServer: AgentSocketServer
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
        // Seed the on-device model catalog (ModelManifest) into the live store.
        // NexusSchemaV7 documents that this runs idempotently from the composition
        // root (NexusSync cannot import ModelCatalog without a package cycle).
        // Without it the `@Query` in Manage Models is empty, so no MLX model can
        // be downloaded or assigned. Idempotent: existing rows are never touched.
        try? ModelCatalog.bootstrap.seed(into: made.mainContext)
        // Developer-only CloudKit schema deploy helper (gated by env flags). No-op in
        // normal launches. See CloudKitSchemaSeeder for the deploy runbook.
        CloudKitSchemaSeeder.runIfRequested(context: made.mainContext)
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
        // Notes content layer (spec §5). Shares the Tasks repository so the
        // checkbox→Task seam (§7) drives the same task lifecycle as the Tasks
        // surface. `Note` is already a synced model in NexusSchemaV9, so the
        // main window + Settings `.modelContainer(container)` already register it.
        self.noteRepository = NotesComposition.makeRepository(
            for: made.mainContext,
            tasks: self.taskRepository,
            observers: self.search.observers
        )
        // People / Contacts (spec §6). `Person` is already a synced model in
        // NexusSchemaV12, so the main window + Settings `.modelContainer(container)`
        // already register it — no separate container registration is needed.
        self.personRepository = PeopleComposition.makeRepository(
            for: made.mainContext,
            observers: self.search.observers
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
        let agentRouter = self.aiRouter
        let agentLifecycle = self.aiGraph.mlxLifecycle
        self.agentComposition = Self.makeAgentComposition(
            modelContext: made.mainContext,
            router: self.aiRouter,
            searchIndex: self.search.searchIndex,
            taskRepository: self.taskRepository,
            nlParser: self.taskParser,
            heroBriefService: heroBriefService,
            meetingTools: self.meetingsComposition.agentTools(),
            ocrPipeline: self.aiGraph.ocrPipeline,
            // Lazy-warm the assigned chat model when the agent surface opens, so
            // an assigned local model serves chat even with "preload on launch"
            // off. Guarded to an assigned, on-disk, not-yet-loaded model (same
            // checks as `preloadMLXIfRequested`) — never loads the `unknown`
            // fallback and no-ops once warm. Foreground + user-initiated, so it
            // does not reintroduce background MLX GPU work.
            warmChatModel: {
                let store = ModelManifestLocalState.Store()
                let assigned =
                    store.currentChatAssignment() != nil
                    && FileManager.default.fileExists(atPath: agentLifecycle.chatFolderURL().path)
                guard assigned, !agentLifecycle.isChatAvailable else { return }
                try? await agentRouter.preloadMLXChat()
            }
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
        self.agentSocketServer = agentInfrastructure.server
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
                .environment(\.noteRepository, noteRepository)
                .environment(\.personRepository, personRepository)
                // People profile meeting history: PeopleFeature cannot import
                // NexusMeetings (feature isolation), so the host resolves a meeting
                // UUID → displayable row via the Meetings repository.
                .environment(
                    \.personMeetingResolver,
                    PersonMeetingResolver { [meetingsComposition] id in
                        try? meetingsComposition.meetingRepository.find(id: id)
                    }
                )
                .environment(\.notificationScheduler, notificationScheduler)
                .environment(\.agentActivityLog, agentActivityLog)
                .environment(\.agentChatViewModel, agentComposition.chatViewModel)
                .environment(\.agentBriefService, agentComposition.briefService)
                .environment(\.meetingsComposition, meetingsComposition)
                .environment(\.meetingNavigationRouter, meetingNavigationRouter)
                .environment(\.focusModeState, focusModeState)
                #if canImport(EventKit) && !os(watchOS)
            .environment(\.calendarEventProvider, EventKitCalendarProvider.shared)
            .environment(\.calendarEventWriter, EventKitCalendarProvider.shared)
                #endif
                // Cheap insurance for non-dashboard states (Focus mode, future
                // sheets) where `NexusWallpaper` is not painted; wallpaper-bearing
                // dashboard ignores safe area and covers this anyway.
                .containerBackground(NexusColor.Background.base, for: .window)
                // Achromatic control tint for the WHOLE main window — mirrors the
                // Settings scene (line ~413). Without it, native Toggle / Picker /
                // segmented / DatePicker controls in the main window (the task
                // inspector, the Capture + Snooze sheets) fall back to system blue,
                // which clashes with the Linear dark theme. `Text.primary` keeps
                // active states achromatic-white; lime stays reserved for primary
                // actions (NexusButton paints its own lime, unaffected by tint).
                .tint(NexusColor.Text.primary)
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
                    // Arm the daily 9:00 overdue digest once authorization is not
                    // denied. Gated the same way the per-task scheduler is — a
                    // denied permission would otherwise make `add(request)` throw.
                    // `try?` because a denied/restricted state is not an error here.
                    if permissionState.status != .denied {
                        try? await TasksComposition.makeOverdueDigestScheduler()
                            .registerDailyDigest()
                    }
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
                // ⌘⌃N is preserved as a menu command. The old borderless
                // `CaptureWindowController` panel was deleted; capture is now an
                // in-window sheet that `ContentView` owns via its own
                // `.onReceive(.nexusOpenCapture)`, so this just posts that.
                Button("Quick Capture") {
                    NotificationCenter.default.post(name: .nexusOpenCapture, object: CapturePane.Mode.task)
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
            // The Settings scene is SEPARATE from the main `Window` and does NOT
            // inherit its `.modelContainer`. Without this, the `@Query` in
            // `ManageModelsSection` has no SwiftData container in scope and Manage
            // Models renders empty (no model rows — the Mac-only "can't manage
            // models" bug). The main window already attaches the same container.
            .modelContainer(container)
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
            NexusMenuBarContent()
        }
        .menuBarExtraStyle(.menu)
    }

    /// Mac path: register `.tombstonePurge`, run once on launch, then drive `runDue` every hour
    /// while the app is foreground. NSBackgroundActivityScheduler integration deferred (decision F2).
    private func bootstrapScheduler() async {
        let job = TombstonePurgeJob.make(container: container, linkableTypes: [TaskItem.self])
        await scheduler.register(job)
        // Calendar/Motion-AI daily auto-rollover (spec §10).
        let madeContainer = container
        await scheduler.register(DailyRolloverJob.makeJob(containerProvider: { madeContainer }))
        await scheduler.runDue()
        // Foreground tick — Timer is fine for a single-job, single-window app.
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            _Concurrency.Task { await scheduler.runDue() }
        }
    }

    private func syncAgentListener(enabled: Bool) {
        if enabled, !agentListenerActive {
            agentSocketServer.start()
            agentListenerActive = true
        } else if !enabled, agentListenerActive {
            agentSocketServer.stop()
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
                try await index.rebuild(
                    from: context,
                    types: TaskItem.self, Note.self, Label.self, Person.self
                )
            } catch {
                print("SearchIndex.rebuild failed on launch: \(error)")
            }
        }
    }

    private static func makeModelContainer(environment: NexusEnvironment) -> ModelContainer {
        do {
            try NexusModelContainer.migrateDefaultStoreToAppGroupIfNeeded(
                extraModels: MeetingsComposition.extraModels
            )
            return try NexusModelContainer.make(
                environment: environment,
                groupContainerIdentifier: NexusModelContainer.appGroupIdentifier,
                extraModels: MeetingsComposition.extraModels,
                // Agent entities are local-only — see `AgentComposition.localOnlyExtraModels`.
                // Without them the container has no AgentThread/AgentMessage tables and every
                // agent turn silently fails to persist.
                localOnlyExtraModels: MeetingsComposition.localOnlyExtraModels
                    + AgentComposition.localOnlyExtraModels
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
                dateExtractor: NLParserDateExtractor(),
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
        let service = AgentSocketServer(
            registry: agentComposition.toolRegistry,
            context: agentContext,
            activityLog: log,
            appVersion: appVersion,
            isEnabled: { UserDefaults.standard.bool(forKey: AgentServiceConstants.mcpEnabledKey) }
        )
        let enabled = UserDefaults.standard.bool(forKey: AgentServiceConstants.mcpEnabledKey)
        if enabled { service.start() }
        return AgentInfrastructure(
            activityLog: log,
            server: service,
            listenerActive: enabled
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
        ocrPipeline: OCRPipeline,
        warmChatModel: @escaping @MainActor () async -> Void
    ) -> AgentComposition {
        let additionalTools =
            NexusAgentToolsExtras.tools() + meetingTools
            + CalendarAgentTools.tools(provider: EventKitCalendarProvider.shared)
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
                warmChatModel: warmChatModel,
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
    let server: AgentSocketServer
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

        // Capture is an in-window overlay now (the borderless panel was
        // deleted), so the menu-bar trigger MUST open + activate the window
        // first — ContentView's `.onReceive(.nexusOpenCapture)` only fires if
        // the window exists. Same pattern as "New Task…" above.
        Button("Quick Capture") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .nexusOpenCapture, object: CapturePane.Mode.task)
            }
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
