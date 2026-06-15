import Foundation
import NexusAgent
import NexusAgentTools
import NexusAgentToolsExtras
import NexusCore
import SwiftData
import TasksFeature

/// Builds the agent registry and runtime context for the running NexusMac process.
@MainActor
enum AgentToolBootstrap {
    static func makeRegistry(
        modelContext: ModelContext,
        embeddingClient: any EmbeddingClient = NLEmbeddingClient(),
        index: SqliteVecIndex,
        ftsSearch: any FTSSearch = NoopFTSSearch()
    ) -> ToolRegistry {
        ToolRegistry(
            tools: AgentToolsAll.tools()
                + NexusAgent.AgentToolBootstrap.agentTools(
                    context: modelContext,
                    embeddingClient: embeddingClient,
                    index: index,
                    ftsSearch: ftsSearch
                )
        )
    }

    static func makeContext(
        modelContext: ModelContext,
        taskRepository: TaskItemRepository,
        searchIndex: SearchIndex,
        nlParser: CompositeNLParser,
        heroBriefService: HeroBriefService,
        now: @escaping @Sendable () -> Date = { .now }
    ) -> AgentContext {
        let parserRef = AnyNLParserRef { input, locale, timestamp in
            await nlParser.parse(input, locale: locale, now: timestamp)
        }
        let heroBriefRef = HeroBriefServiceRef { context, timestamp in
            let todayQuery = TodayQuery()
            let archivedProjectIDs =
                (try? ProjectRepository(context: context).archivedProjectIDs()) ?? []
            let overdue =
                (try? todayQuery.overdue(now: timestamp, excludingProjectIDs: archivedProjectIDs)
                    .apply(in: context)) ?? []
            let today =
                (try? todayQuery.today(now: timestamp, excludingProjectIDs: archivedProjectIDs)
                    .apply(in: context)) ?? []
            let noDate =
                (try? todayQuery.noDate(excludingProjectIDs: archivedProjectIDs)
                    .apply(in: context)) ?? []
            let firstTitles = (overdue + today + noDate).prefix(3).map(\.title)
            let counts = HeroBriefService.Counts(
                overdue: overdue.count,
                today: today.count,
                noDate: noDate.count,
                awaiting: 0
            )
            return await heroBriefService.brief(
                for: counts,
                firstTitles: Array(firstTitles),
                now: timestamp
            )
        }
        return AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(taskRepository),
            searchIndex: searchIndex,
            now: now,
            nlParser: parserRef,
            heroBriefService: heroBriefRef,
            modelContainer: ModelContainerRef(modelContext.container)
        )
    }
}
