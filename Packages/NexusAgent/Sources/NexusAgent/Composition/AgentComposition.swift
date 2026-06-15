import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import NexusUI
import SwiftData

public enum AgentPlatform: String, Sendable {
    case mac
    case iOS
}

@MainActor
public struct AgentComposition {
    /// The agent's SwiftData `@Model` entities, for the composition root to
    /// register with `NexusModelContainer` (NexusSync cannot import NexusAgent —
    /// that would be a package cycle — so, exactly like `MeetingsComposition`,
    /// the model list must be handed in from the app).
    ///
    /// **These are LOCAL-ONLY (never CloudKit-synced).** Two reasons:
    /// 1. `CloudKitSchemaSeeder` already documents "agent models are not part of
    ///    the synced schema" — agent threads/messages are device-local working
    ///    state, not iCloud-mirrored user content.
    /// 2. The app ships on a PRODUCTION CloudKit environment (TestFlight), where
    ///    SwiftData does NOT auto-create new record types — a synced schema needs
    ///    a manual dev→prod CloudKit deploy. Registering these local-only keeps
    ///    the synced/CloudKit configuration byte-identical, so the user's real
    ///    tasks/projects/meetings are untouched.
    ///
    /// Cross-device agent history (moving these to the synced config) is a
    /// separate product decision, deliberately not bundled here.
    ///
    /// Regression context: before this list was wired into the apps, the agent's
    /// stores ran against a container whose schema lacked these entities, so every
    /// `insert`/`fetch` silently no-op'd — threads/messages never persisted and
    /// every turn ended `.rejected` (input reverted, no message bubble) on both
    /// platforms.
    ///
    /// `nonisolated` so the composition root (and tests) can read the list
    /// without hopping to the MainActor — it is immutable metatype data with no
    /// actor state, mirroring the non-isolated `MeetingsComposition.extraModels`.
    nonisolated public static let localOnlyExtraModels: [any PersistentModel.Type] = [
        AgentThread.self,
        AgentMessage.self,
        AgentMemoryEntry.self,
        AgentAuditLog.self,
        AgentSchedule.self,
        ItemEmbedding.self,
    ]

    public let runtime: AgentRuntime
    public let chatViewModel: AgentChatViewModel
    public let settingsContext: AgentSettingsContext
    public let briefService: AgentBriefService
    public let pruner: AgentMessagePruner
    public let backfillJob: BackfillEmbeddingsJob
    public let dispatcher: EmbeddingDispatcher
    public let index: SqliteVecIndex
    public let toolRegistry: ToolRegistry
    public let scheduler: any AgentScheduler
    public let scheduleRunner: AgentScheduleRunner
    public let watchHandler: WatchAgentHandler?

    // MARK: - Proactive Insights (Task 7–8)

    /// Foreground-driven orchestration hub. App shells call
    /// `insightCoordinator.runDueInsights(now: .now)` on each foreground transition.
    public let insightCoordinator: InsightCoordinator
    /// Observable pending-insight queue; inject into `TodayDashboard` via
    /// `.environment(\.pendingInsightStore, agentComposition.pendingInsightStore)`.
    public let pendingInsightStore: PendingInsightStore
    /// Cooldown store shared by coordinator and the Today dismiss handler.
    public let insightCooldownStore: InsightCooldownStore
    /// Shared proposal coordinator for applying insight mutations.
    public let proposalCoordinator: ProposalCoordinator

    private let maintenanceRunner: AgentMaintenanceRunner

    // swiftlint:disable:next function_body_length function_parameter_count
    public static func make(
        platform: AgentPlatform,
        context: ModelContext,
        router: AIRouter,
        searchIndex: SearchIndex,
        taskRepository: TaskItemRepository,
        aiLiveData: AISettingsLiveData? = nil,
        agentContext: AgentContext? = nil,
        additionalTools: [any AgentTool] = [],
        ocrPipeline: OCRPipeline? = nil,
        chatModelAvailability: (@MainActor () -> Bool)? = nil,
        warmChatModel: (@MainActor () async -> Void)? = nil,
        chatReadiness: (@MainActor () -> AssistantReadiness)? = nil,
        /// Optional calendar-event provider for the overload insight.
        /// Defaults to `{ [] }` (no events). Apps supply their EventKit provider.
        eventsProvider: (@MainActor () async -> [CalendarEvent])? = nil,
        /// Optional meeting-decompose candidate provider.
        /// Defaults to `{ [] }` (no meetings). Apps wire a meeting repository query.
        /// FLAG: this param is optional; a `{ [] }` fallback is acceptable for
        /// callers that cannot reach `MeetingRepository` at composition time.
        meetingCandidatesProvider: (@MainActor () -> [MeetingDecomposeCandidate])? = nil,
        legacyBrief: @escaping @Sendable (AgentBriefRequest) async -> String
    ) throws -> AgentComposition {
        let stores = AgentStores(context: context)
        try DefaultSchedulesSeed.runIfNeeded(store: stores.scheduleStore)
        let embedding = try makeEmbeddingInfrastructure(context: context, searchIndex: searchIndex)
        let tools = makeTools(context: context, embedding: embedding, additionalTools: additionalTools)
        let registry = ToolRegistry(tools: tools)
        let resolvedAgentContext = makeAgentContext(
            provided: agentContext,
            context: context,
            searchIndex: searchIndex,
            taskRepository: taskRepository
        )
        let toolDispatcher = ToolDispatcher(
            registry: registry,
            modelContext: context,
            agentContext: resolvedAgentContext
        )
        let contextBuilder = makeContextBuilder(
            context: context,
            stores: stores,
            embedding: embedding,
            tools: tools
        )
        #if canImport(Vision)
        let runtime = AgentRuntime(
            router: router,
            threadStore: stores.threadStore,
            messageStore: stores.messageStore,
            contextBuilder: contextBuilder,
            dispatcher: toolDispatcher,
            ocrPipeline: ocrPipeline
        )
        #else
        let runtime = AgentRuntime(
            router: router,
            threadStore: stores.threadStore,
            messageStore: stores.messageStore,
            contextBuilder: contextBuilder,
            dispatcher: toolDispatcher
        )
        #endif
        let undoCoordinator = AgentUndoCoordinator(
            dispatcher: toolDispatcher,
            modelContext: context
        )
        let backfillJob = BackfillEmbeddingsJob(
            context: context,
            dispatcher: embedding.dispatcher,
            index: embedding.index
        )
        let chatCoordinator = ProposalCoordinator(dispatcher: toolDispatcher)

        // MARK: - Proactive insights infrastructure
        let pendingStore = PendingInsightStore()
        let cooldownStore = InsightCooldownStore()
        let dayPlanRunner = FoundationComposition.makeLocalRunner(
            modelContext: context,
            router: router
        )
        let prefs = UserDefaultsCalendarPreferencesStore().load()
        let capacity = CapacityModel.fromPreferences(prefs)
        let resolvedEventsProvider: @MainActor () async -> [CalendarEvent] = eventsProvider ?? { [] }
        let resolvedMeetingsProvider: @MainActor () -> [MeetingDecomposeCandidate] =
            meetingCandidatesProvider ?? { [] }
        let insightCoordinator = InsightCoordinator(
            cooldown: cooldownStore,
            pending: pendingStore,
            tasks: {
                let mc = context
                let all =
                    (try? mc.fetch(
                        FetchDescriptor<TaskItem>(
                            predicate: #Predicate { $0.deletedAt == nil })))
                    ?? []
                let openRaw = TaskStatus.open.rawValue
                let open = all.filter { $0.statusRaw == openRaw }
                return open.compactMap { task -> ScheduledItem? in
                    guard let day = task.dueAt else { return nil }
                    let mins = task.estimatedDurationSeconds.map { max(1, Int($0) / 60) } ?? 30
                    return ScheduledItem(id: task.id, durationMinutes: mins, day: day)
                }
            },
            events: resolvedEventsProvider,
            capacity: { capacity },
            meetingsNeedingDecompose: resolvedMeetingsProvider,
            dayPlanRunner: dayPlanRunner,
            dayPlanNumbers: {
                let mc = context
                let all =
                    (try? mc.fetch(
                        FetchDescriptor<TaskItem>(
                            predicate: #Predicate { $0.deletedAt == nil })))
                    ?? []
                let openRaw = TaskStatus.open.rawValue
                let open = all.filter { $0.statusRaw == openRaw }
                let today = Date()
                let eod = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today
                let dueToday = open.filter { ($0.dueAt ?? .distantFuture) <= eod }
                return "\(dueToday.count) due today, \(open.count) total open"
            },
            makeDecomposeCoordinator: {
                MeetingDecomposeCoordinator(
                    runner: dayPlanRunner,
                    scheduler: SlotScheduler(),
                    workload: WorkloadAnalyzer(),
                    capacity: capacity,
                    prefs: prefs,
                    events: [],
                    now: Date()
                )
            }
        )

        // iOS chat is extraction-only (no tool-calling): pre-stuff a context via
        // ContextAssembler, reusing the same hybrid retriever the ContextBuilder uses.
        // Mac tool-calls instead, so it gets no closure (see AssistantChatConfig).
        let iosChatAssembler: ContextAssembler? =
            platform == .iOS
            ? ContextAssembler(
                agentContext: resolvedAgentContext,
                retriever: AgentSearchSemanticTool(
                    embeddingClient: embedding.embeddingClient,
                    index: embedding.index,
                    ftsSearch: embedding.ftsSearch,
                    context: context))
            : nil
        let iosAssembleContext: (@MainActor (ContextRecipe, ContextFocus, Date) async -> String)?
        if let assembler = iosChatAssembler {
            iosAssembleContext = { recipe, focus, now in
                await assembler.assemble(recipe, focus: focus, now: now)
                    .renderedBlocks().joined(separator: "\n\n")
            }
        } else {
            iosAssembleContext = nil
        }
        let chatViewModel = AgentChatViewModel(
            runtime: runtime,
            threadStore: stores.threadStore,
            messageStore: stores.messageStore,
            memoryStore: stores.memoryStore,
            voiceCapture: .live(router: router),
            chatModelAvailability: chatModelAvailability,
            warmChatModel: warmChatModel,
            chatConfig: platform == .mac ? .mac : .iOS,
            proposalCoordinator: chatCoordinator,
            readinessProbe: chatReadiness,
            assembleContext: iosAssembleContext
        )
        let settingsContext = AgentSettingsContext(
            memoryStore: stores.memoryStore,
            scheduleStore: stores.scheduleStore,
            auditContext: context,
            backfillJob: backfillJob,
            undoCoordinator: undoCoordinator,
            aiLiveData: aiLiveData
        )
        let briefService = AgentBriefService(
            runtime: runtime,
            threadStore: stores.threadStore,
            legacy: legacyBrief,
            // Default ON when unset, matching the @AppStorage master switch (= true) and
            // VacationModeGate. Plain `.bool(forKey:)` returns false for an unset key, which
            // silently disabled the AI brief on every fresh install. (Cloud-consent/quota is
            // enforced separately by the provider, so defaulting this feature flag ON is safe.)
            isEnabled: {
                UserDefaults.standard.object(forKey: NexusPreferences.Keys.agentEnabled) as? Bool ?? true
            },
            dailyNoteWriter: AgentBriefDailyNoteWriter(modelContext: context)
        )
        let scheduleRunner = AgentScheduleRunner(
            runtime: runtime,
            threadStore: stores.threadStore,
            scheduleStore: stores.scheduleStore,
            messageStore: stores.messageStore,
            notificationCenter: SystemNotificationCenter()
        )
        let platformServices = makePlatformServices(
            platform: platform,
            scheduleStore: stores.scheduleStore,
            runner: scheduleRunner,
            runtime: runtime,
            threadStore: stores.threadStore
        )

        return AgentComposition(
            runtime: runtime,
            chatViewModel: chatViewModel,
            settingsContext: settingsContext,
            briefService: briefService,
            pruner: AgentMessagePruner(),
            backfillJob: backfillJob,
            dispatcher: embedding.dispatcher,
            index: embedding.index,
            toolRegistry: registry,
            scheduler: platformServices.scheduler,
            scheduleRunner: scheduleRunner,
            watchHandler: platformServices.watchHandler,
            insightCoordinator: insightCoordinator,
            pendingInsightStore: pendingStore,
            insightCooldownStore: cooldownStore,
            proposalCoordinator: chatCoordinator,
            maintenanceRunner: AgentMaintenanceRunner()
        )
    }

    public func runActiveMaintenance(context: ModelContext) {
        maintenanceRunner.run(
            pruner: pruner,
            backfillJob: backfillJob,
            context: context
        )
    }

    private static func makeEmbeddingInfrastructure(
        context: ModelContext,
        searchIndex: SearchIndex
    ) throws -> AgentEmbeddingInfrastructure {
        let embeddingClient = NLEmbeddingClient()
        let index = try SqliteVecIndex(path: agentIndexPath())
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: embeddingClient,
            index: index,
            context: context
        )
        return AgentEmbeddingInfrastructure(
            embeddingClient: embeddingClient,
            index: index,
            dispatcher: dispatcher,
            ftsSearch: NexusSearchFTS(index: searchIndex)
        )
    }

    private static func makeTools(
        context: ModelContext,
        embedding: AgentEmbeddingInfrastructure,
        additionalTools: [any AgentTool]
    ) -> [any AgentTool] {
        CoreTaskTools.all()
            + AgentToolBootstrap.agentTools(
                context: context,
                embeddingClient: embedding.embeddingClient,
                index: embedding.index,
                ftsSearch: embedding.ftsSearch
            )
            + additionalTools
    }

    private static func makeAgentContext(
        provided: AgentContext?,
        context: ModelContext,
        searchIndex: SearchIndex,
        taskRepository: TaskItemRepository
    ) -> AgentContext {
        provided
            ?? AgentContext(
                modelContext: ModelContextRef(context),
                taskRepository: TaskItemRepositoryRef(taskRepository),
                searchIndex: searchIndex,
                now: { .now },
                modelContainer: ModelContainerRef(context.container)
            )
    }

    private static func makeContextBuilder(
        context: ModelContext,
        stores: AgentStores,
        embedding: AgentEmbeddingInfrastructure,
        tools: [any AgentTool]
    ) -> ContextBuilder {
        ContextBuilder(
            memoryStore: stores.memoryStore,
            messageStore: stores.messageStore,
            retriever: AgentSearchSemanticTool(
                embeddingClient: embedding.embeddingClient,
                index: embedding.index,
                ftsSearch: embedding.ftsSearch,
                context: context
            ),
            tools: tools
        )
    }

    private static func makePlatformServices(
        platform: AgentPlatform,
        scheduleStore: AgentScheduleStore,
        runner: AgentScheduleRunner,
        runtime: AgentRuntime,
        threadStore: AgentThreadStore
    ) -> AgentPlatformServices {
        switch platform {
        case .mac:
            return AgentPlatformServices(
                scheduler: MacAgentScheduler(
                    scheduleStore: scheduleStore,
                    onFire: { scheduleID in
                        _ = try? await runner.run(scheduleID: scheduleID)
                    }
                ),
                watchHandler: nil
            )
        case .iOS:
            #if os(iOS)
            return AgentPlatformServices(
                scheduler: IOSAgentScheduler(
                    scheduleStore: scheduleStore,
                    onFire: { scheduleID in
                        _ = try? await runner.run(scheduleID: scheduleID)
                    },
                    bgScheduler: SystemBGTaskScheduler()
                ),
                watchHandler: WatchAgentHandler(
                    runtime: runtime,
                    threadStore: threadStore,
                    notificationCenter: SystemNotificationCenter()
                )
            )
            #else
            return AgentPlatformServices(
                scheduler: AgentSchedulerNoop(),
                watchHandler: nil
            )
            #endif
        }
    }

    private static func agentIndexPath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appending(path: "Nexus/Agent", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "embeddings.sqlite").path
    }
}

@MainActor
private struct AgentStores {
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
    let memoryStore: AgentMemoryStore
    let scheduleStore: AgentScheduleStore

    init(context: ModelContext) {
        self.threadStore = AgentThreadStore(context: context)
        self.messageStore = AgentMessageStore(context: context)
        self.memoryStore = AgentMemoryStore(context: context)
        self.scheduleStore = AgentScheduleStore(context: context)
    }
}

private struct AgentEmbeddingInfrastructure {
    let embeddingClient: NLEmbeddingClient
    let index: SqliteVecIndex
    let dispatcher: EmbeddingDispatcher
    let ftsSearch: NexusSearchFTS
}

private struct AgentPlatformServices {
    let scheduler: any AgentScheduler
    let watchHandler: WatchAgentHandler?
}

@MainActor
private final class AgentMaintenanceRunner {
    private var backfillTask: Task<Void, Never>?

    func run(
        pruner: AgentMessagePruner,
        backfillJob: BackfillEmbeddingsJob,
        context: ModelContext
    ) {
        _ = try? pruner.runIfNeeded(context: context)
        guard backfillTask == nil else { return }

        backfillTask = Task { @MainActor [weak self] in
            _ = try? await backfillJob.runIfIdle()
            self?.backfillTask = nil
        }
    }
}
