import BackgroundTasks
import NexusAI
import NexusAgent
import NexusAgentTools
import NexusCore
import NexusMeetings
import NexusSearch
import NexusSync
import NexusUI
import SwiftData
import SwiftUI
import TasksFeature
import UserNotifications

#if canImport(WidgetKit)
import WidgetKit
#endif

// The iOS composition root wires every subsystem (model container, AI graph,
// agent, meetings, scheduler, welcome flow) plus the iOS root-view shell. It
// grows by ~1 stored prop + wiring line per feature by design — same
// structural rationale as the file_length disable on NexusMacApp; the MLX
// preload + in-process rebind wiring added the lines that crossed 600.
// swiftlint:disable file_length

@main
struct NexusiOSApp: App {
    static let tombstonePurgeTaskID = "com.kacperpietrzyk.Nexus.tombstonePurge"

    private let container: ModelContainer
    private let environment: NexusEnvironment
    private let search: SearchSubsystem
    private let aiRouter: AIRouter
    // Strong ref — the AIGraph owns the MLX lifecycle (background idle sweep)
    // and the memory guard (OS memory-warning observer torn down in deinit).
    // Dropping it silently disables MLX unload-on-pressure.
    private let aiGraph: AIComposition.AIGraph
    private let taskParser: CompositeNLParser
    private let taskRepository: TaskItemRepository
    private let notificationScheduler: NotificationScheduler
    private let agentComposition: AgentComposition
    private let meetingsComposition: MeetingsComposition
    private let scheduler: Scheduler
    // Strong ref — UNUserNotificationCenter does NOT retain its delegate.
    private let actionHandler: NotificationActionHandler
    // Retained for the process lifetime — its kicked-off MLX downloads
    // (multi-GB) must outlive the welcome sheet.
    private let welcomeMLXDownloads: WelcomeMLXDownloadCoordinator

    init() {
        NexusPreferences.migrateLegacyAgentPreloadSpeechKey()
        UserDefaultsQuietHoursStore.migrateFromStandardIfNeeded()
        let env = NexusEnvironment.current
        let made = Self.makeModelContainer(environment: env)
        self.environment = env
        self.container = made
        self.search = SearchSubsystem.makeLive()
        let graph = AIComposition.makeGraph(container: made)
        self.aiGraph = graph
        self.aiRouter = graph.router
        Self.preloadWhisperKitIfRequested(router: self.aiRouter)
        Self.preloadMLXIfRequested(router: self.aiRouter, lifecycle: graph.mlxLifecycle)
        self.taskParser = TasksComposition.makeParser(router: self.aiRouter)
        let notifScheduler = TasksComposition.makeNotificationScheduler()
        self.notificationScheduler = notifScheduler
        self.taskRepository = TasksComposition.makeRepository(
            for: made.mainContext,
            notifications: NotificationSchedulingAdapter(scheduler: notifScheduler),
            snapshotPusher: WCSessionWatchSnapshotPusher()
        )
        self.meetingsComposition = Self.makeMeetingsComposition(
            context: made.mainContext,
            router: self.aiRouter,
            taskRepository: self.taskRepository
        )
        let heroBriefService = HeroBriefService(router: self.aiRouter)
        let agentComposition = Self.makeAgentComposition(
            dependencies: .init(
                modelContext: made.mainContext,
                router: self.aiRouter,
                searchIndex: self.search.searchIndex,
                taskRepository: self.taskRepository,
                heroBriefService: heroBriefService,
                meetingTools: self.meetingsComposition.agentTools(),
                ocrPipeline: graph.ocrPipeline,
                mlxLifecycle: graph.mlxLifecycle
            )
        )
        self.agentComposition = agentComposition
        TaskIntentRuntime.configure(parser: self.taskParser, repository: self.taskRepository)
        self.actionHandler = Self.makeNotificationActionHandler(
            repository: self.taskRepository,
            scheduler: notifScheduler
        )
        let scheduler = Scheduler()
        self.scheduler = scheduler
        let router = self.aiRouter
        self.welcomeMLXDownloads = WelcomeMLXDownloadCoordinator(
            onChatAssigned: { try? await router.reloadMLXChat() },
            onEmbedderAssigned: { try? await router.reloadMLXEmbedder() }
        )

        // Rebuild the index from the live store on launch. D-0d-7: index is reproducible.
        let mainContext = made.mainContext
        let index = self.search.searchIndex
        Self.rebuildSearchIndexOnLaunch(context: mainContext, index: index)

        Self.registerBackgroundTasks(
            scheduler: scheduler,
            container: made,
            agentComposition: agentComposition
        )
    }

    private static func preloadWhisperKitIfRequested(router: AIRouter) {
        guard UserDefaults.standard.bool(forKey: NexusPreferences.Keys.agentVoicePreloadWhisperKit) else {
            return
        }

        _Concurrency.Task.detached(priority: .utility) {
            try? await router.preloadWhisperKit()
        }
    }

    /// Warms the on-device MLX provider(s) at launch (breaks the
    /// availability/load cycle). Mirrors the Mac path exactly — see
    /// `NexusMacApp.preloadMLXIfRequested` for the chat-toggle /
    /// embedder-no-toggle / first-launch-guard rationale.
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

    /// Probe for the agent chat surface: is an on-device chat model actually downloaded
    /// and assigned? Mirrors the `chatReady` check in `preloadMLXIfRequested`. Used to
    /// show a "download the model" banner in the agent — Apple Intelligence being on is
    /// NOT sufficient (it can't serve the agent's structured tool-calling turns), so a
    /// router capability probe would give a false negative; only a concrete MLX chat
    /// model makes the agent usable on device.
    private static func makeChatModelAvailabilityProbe(
        lifecycle: MLXLifecycleController
    ) -> @MainActor () -> Bool {
        { @MainActor in
            let store = ModelManifestLocalState.Store()
            return store.currentChatAssignment() != nil
                && FileManager.default.fileExists(atPath: lifecycle.chatFolderURL().path)
        }
    }

    var body: some Scene {
        WindowGroup {
            NexusiOSRootView(
                environment: environment,
                container: container,
                search: search,
                aiRouter: aiRouter,
                taskParser: taskParser,
                taskRepository: taskRepository,
                notificationScheduler: notificationScheduler,
                agentComposition: agentComposition,
                meetingsComposition: meetingsComposition,
                scheduler: scheduler,
                welcomeMLXDownloads: welcomeMLXDownloads,
                mlxLifecycle: aiGraph.mlxLifecycle
            )
        }
        .modelContainer(container)
    }

    /// Submits a `BGProcessingTaskRequest` for ~24h from now. Called on launch and after each
    /// successful background run. `requiresExternalPower = false` because purge work is cheap.
    static func scheduleNextBGTask() {
        let request = BGProcessingTaskRequest(identifier: tombstonePurgeTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 24)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // No-op: simulator + missing entitlement both throw here. Handled by foreground retry.
        }
    }

    private struct AgentCompositionDependencies {
        let modelContext: ModelContext
        let router: AIRouter
        let searchIndex: SearchIndex
        let taskRepository: TaskItemRepository
        let heroBriefService: HeroBriefService
        let meetingTools: [any AgentTool]
        let ocrPipeline: OCRPipeline
        let mlxLifecycle: MLXLifecycleController
    }

    /// Background callback. `task.expirationHandler` cancels the work if the system reclaims the
    /// budget; otherwise we run the scheduler's force-run path and reschedule.
    static func handle(task: BGTask, scheduler: Scheduler, container: ModelContainer) {
        scheduleNextBGTask()
        let work = _Concurrency.Task {
            await scheduler.runNow(.tombstonePurge)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    static func handleAgentScheduleTask(
        task: BGTask,
        agentComposition: AgentComposition
    ) {
        let completion = BGTaskCompletionGuard()
        let work = _Concurrency.Task { @MainActor in
            guard let scheduler = agentComposition.scheduler as? IOSAgentScheduler else {
                completion.complete(success: false) { task.setTaskCompleted(success: $0) }
                return
            }
            await scheduler.runBackgroundTask()
            guard !Task.isCancelled else {
                completion.complete(success: false) { task.setTaskCompleted(success: $0) }
                return
            }

            completion.complete(success: true) { task.setTaskCompleted(success: $0) }
        }
        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false) { task.setTaskCompleted(success: $0) }
        }
    }

    private static func rebuildSearchIndexOnLaunch(
        context: ModelContext,
        index: SearchIndex
    ) {
        _Concurrency.Task { @MainActor in
            do {
                try await index.rebuild(from: context, types: TaskItem.self)
            } catch {
                print("SearchIndex.rebuild failed on launch: \(error)")
            }
        }
    }

    private static func registerBackgroundTasks(
        scheduler: Scheduler,
        container: ModelContainer,
        agentComposition: AgentComposition
    ) {
        // BGTaskScheduler.register MUST be called before applicationDidFinishLaunching returns.
        // SwiftUI's `init` runs early enough for this.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.tombstonePurgeTaskID,
            using: nil
        ) { task in
            Self.handle(task: task, scheduler: scheduler, container: container)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: IOSAgentScheduler.bgTaskIdentifier,
            using: nil
        ) { task in
            Self.handleAgentScheduleTask(
                task: task,
                agentComposition: agentComposition
            )
        }
        // Keep multi-GB model downloads alive when the app is backgrounded.
        // The download session continues via URLSession background transfers;
        // this BGTask wakes the process if iOS suspends it mid-download.
        ModelDownloadManager.registerBackgroundHandler {}
    }

    private static func makeAgentComposition(
        dependencies: AgentCompositionDependencies
    ) -> AgentComposition {
        do {
            return try AgentComposition.make(
                platform: .iOS,
                context: dependencies.modelContext,
                router: dependencies.router,
                searchIndex: dependencies.searchIndex,
                taskRepository: dependencies.taskRepository,
                aiLiveData: AISettingsLiveData(router: dependencies.router),
                additionalTools: dependencies.meetingTools,
                ocrPipeline: dependencies.ocrPipeline,
                chatModelAvailability: Self.makeChatModelAvailabilityProbe(
                    lifecycle: dependencies.mlxLifecycle
                ),
                legacyBrief: makeLegacyBrief(using: dependencies.heroBriefService)
            )
        } catch {
            fatalError("Failed to compose Nexus Agent: \(error)")
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

    private static func makeNotificationActionHandler(
        repository: TaskItemRepository,
        scheduler: NotificationScheduler
    ) -> NotificationActionHandler {
        let handler = NotificationActionHandler(repository: repository, scheduler: scheduler)
        UNUserNotificationCenter.current().delegate = handler
        return handler
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

private struct NexusiOSRootView: View {
    @State private var exportPickerPresented = false
    @State private var permissionState = NotificationPermissionState()
    @State private var watchRelay: WatchConnectivityRelay?
    @State private var focusModeState = FocusModeState()
    @State private var welcomePresented: Bool
    @AppStorage(NexusPreferences.Keys.welcomeShown) private var welcomeShown: Bool = false

    let environment: NexusEnvironment
    let container: ModelContainer
    let search: SearchSubsystem
    let aiRouter: AIRouter
    let taskParser: CompositeNLParser
    let taskRepository: TaskItemRepository
    let notificationScheduler: NotificationScheduler
    let agentComposition: AgentComposition
    let meetingsComposition: MeetingsComposition
    let scheduler: Scheduler
    let welcomeMLXDownloads: WelcomeMLXDownloadCoordinator
    let mlxLifecycle: MLXLifecycleController

    init(
        environment: NexusEnvironment,
        container: ModelContainer,
        search: SearchSubsystem,
        aiRouter: AIRouter,
        taskParser: CompositeNLParser,
        taskRepository: TaskItemRepository,
        notificationScheduler: NotificationScheduler,
        agentComposition: AgentComposition,
        meetingsComposition: MeetingsComposition,
        scheduler: Scheduler,
        welcomeMLXDownloads: WelcomeMLXDownloadCoordinator,
        mlxLifecycle: MLXLifecycleController
    ) {
        self.environment = environment
        self.container = container
        self.search = search
        self.aiRouter = aiRouter
        self.taskParser = taskParser
        self.taskRepository = taskRepository
        self.notificationScheduler = notificationScheduler
        self.agentComposition = agentComposition
        self.meetingsComposition = meetingsComposition
        self.scheduler = scheduler
        self.welcomeMLXDownloads = welcomeMLXDownloads
        self.mlxLifecycle = mlxLifecycle
        self._welcomePresented = State(
            initialValue: !UserDefaults.standard.bool(forKey: NexusPreferences.Keys.welcomeShown)
        )
    }

    var body: some View {
        configuredContent
            .background {
                ExportFolderPicker(isPresented: $exportPickerPresented) { folder in
                    _Concurrency.Task {
                        _ = try? await MarkdownExporter.export(
                            container: container,
                            types: TaskItem.self,
                            to: folder
                        )
                    }
                }
            }
            .modifier(
                TombstonePurgeLifecycleModifier(
                    container: container,
                    scheduler: scheduler
                )
            )
            .modifier(
                AgentLifecycleModifier(
                    container: container,
                    agentComposition: agentComposition
                )
            )
            .modifier(NotificationPermissionLifecycleModifier(permissionState: $permissionState))
            .modifier(
                WatchRelayLifecycleModifier(
                    watchRelay: $watchRelay,
                    taskParser: taskParser,
                    taskRepository: taskRepository,
                    agentComposition: agentComposition
                )
            )
            .modifier(WidgetTimelineReloadModifier())
            .modifier(
                WelcomeFlowPresenter(
                    isPresented: $welcomePresented,
                    welcomeShown: $welcomeShown,
                    welcomeMLXDownloads: welcomeMLXDownloads
                )
            )
    }

    private var configuredContent: some View {
        baseContent
            .environment(\.searchSubsystem, search)
            .environment(\.aiRouter, aiRouter)
            .environment(\.taskParser, taskParser)
            .environment(\.taskRepository, taskRepository)
            .environment(\.notificationScheduler, notificationScheduler)
            .environment(\.agentChatViewModel, agentComposition.chatViewModel)
            .environment(\.agentBriefService, agentComposition.briefService)
            .environment(\.meetingsComposition, meetingsComposition)
            .environment(\.focusModeState, focusModeState)
            #if canImport(EventKit) && !os(watchOS)
        .environment(\.calendarEventProvider, EventKitCalendarProvider.shared)
            #endif
    }

    private var baseContent: some View {
        ContentView(
            cloudKitEnabled: environment.cloudKitEnabled,
            containerIdentifier: environment.cloudKitContainerIdentifier,
            permissionState: permissionState,
            agentSettingsContext: agentComposition.settingsContext,
            manageModelsContent: AnyView(
                ManageModelsSection(
                    localStateStore: ModelManifestLocalState.Store(),
                    downloadManager: welcomeMLXDownloads.manager,
                    lifecycle: mlxLifecycle,
                    onChatReassigned: { [aiRouter] in try? await aiRouter.reloadMLXChat() },
                    onEmbedderReassigned: { [aiRouter] in try? await aiRouter.reloadMLXEmbedder() }
                )
            ),
            onExportRequested: { exportPickerPresented = true }
        )
    }
}

private struct TombstonePurgeLifecycleModifier: ViewModifier {
    let container: ModelContainer
    let scheduler: Scheduler

    func body(content: Content) -> some View {
        content
            .task {
                let job = TombstonePurgeJob.make(
                    container: container,
                    linkableTypes: [TaskItem.self]
                )
                await scheduler.register(job)
                await scheduler.runDue()
                NexusiOSApp.scheduleNextBGTask()
            }
    }
}

private struct AgentLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer
    let agentComposition: AgentComposition

    func body(content: Content) -> some View {
        content
            .task {
                await agentComposition.scheduler.start()
            }
            .task {
                if scenePhase == .active {
                    agentComposition.runActiveMaintenance(context: container.mainContext)
                    await iosAgentScheduler?.foregroundCatchUp()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                agentComposition.runActiveMaintenance(context: container.mainContext)
                _Concurrency.Task { @MainActor in
                    await iosAgentScheduler?.foregroundCatchUp()
                }
            }
    }

    private var iosAgentScheduler: IOSAgentScheduler? {
        agentComposition.scheduler as? IOSAgentScheduler
    }
}

private struct NotificationPermissionLifecycleModifier: ViewModifier {
    @Binding var permissionState: NotificationPermissionState

    func body(content: Content) -> some View {
        content
            .task {
                await NotificationCategories.registerAll(on: SystemNotificationCenter())
                await permissionState.refresh()
                await permissionState.requestIfNeeded()
            }
    }
}

private struct WatchRelayLifecycleModifier: ViewModifier {
    @Binding var watchRelay: WatchConnectivityRelay?

    let taskParser: CompositeNLParser
    let taskRepository: TaskItemRepository
    let agentComposition: AgentComposition

    func body(content: Content) -> some View {
        content
            .task {
                guard watchRelay == nil else { return }
                let handler = WatchPayloadHandler(
                    parser: taskParser,
                    repository: taskRepository,
                    agentPromptHandler: watchAgentPromptHandler
                )
                let relay = WatchConnectivityRelay(handler: handler)
                relay.activate()
                watchRelay = relay
            }
    }

    private var watchAgentPromptHandler: WatchAgentPromptHandling? {
        guard let watchHandler = agentComposition.watchHandler else { return nil }
        return { prompt in
            (try await watchHandler.handle(prompt: prompt)).text
        }
    }
}

private struct WidgetTimelineReloadModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                #if canImport(WidgetKit)
                WidgetKit.WidgetCenter.shared.reloadAllTimelines()
                #endif
            }
    }
}

private struct MeetingsCompositionKey: EnvironmentKey {
    static let defaultValue: MeetingsComposition? = nil
}

extension EnvironmentValues {
    var meetingsComposition: MeetingsComposition? {
        get { self[MeetingsCompositionKey.self] }
        set { self[MeetingsCompositionKey.self] = newValue }
    }
}

private struct WelcomeFlowPresenter: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var welcomeShown: Bool

    let welcomeMLXDownloads: WelcomeMLXDownloadCoordinator

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                isPresented: $isPresented,
                onDismiss: { welcomeShown = true },
                content: {
                    WelcomeFlowView(
                        onFinished: {
                            welcomeShown = true
                            isPresented = false
                        },
                        // iOS has no Meetings step — the MLX download step is
                        // the only extra screen (omitted if catalog failed).
                        extraScreens: welcomeMLXDownloads.extraScreens()
                    )
                    .interactiveDismissDisabled(true)
                }
            )
    }
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
