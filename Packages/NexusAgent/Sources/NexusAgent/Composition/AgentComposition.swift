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
        let chatViewModel = AgentChatViewModel(
            runtime: runtime,
            threadStore: stores.threadStore,
            messageStore: stores.messageStore,
            memoryStore: stores.memoryStore,
            voiceCapture: .live(router: router),
            chatModelAvailability: chatModelAvailability
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
            }
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
                now: { .now }
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
