import Foundation
import NexusAgentTools
import SwiftData

public enum AgentToolBootstrap {
    @MainActor
    public static func agentTools(
        context: ModelContext,
        embeddingClient: any EmbeddingClient = NLEmbeddingClient(),
        index: SqliteVecIndex,
        ftsSearch: any FTSSearch = NoopFTSSearch()
    ) -> [any AgentTool] {
        let memoryStore = AgentMemoryStore(context: context)
        return [
            AgentRememberTool(store: memoryStore),
            AgentForgetTool(store: memoryStore),
            AgentRecallTool(store: memoryStore),
            AgentLinkItemsTool(context: context),
            AgentUnlinkItemsTool(context: context),
            AgentNoopTool(),
            AgentActivityLogTool(context: context),
            AgentSearchSemanticTool(
                embeddingClient: embeddingClient,
                index: index,
                ftsSearch: ftsSearch,
                context: context
            ),
        ]
    }

    @MainActor
    public static func makeRegistry(
        context: ModelContext,
        embeddingClient: any EmbeddingClient = NLEmbeddingClient(),
        index: SqliteVecIndex,
        ftsSearch: any FTSSearch = NoopFTSSearch()
    ) -> ToolRegistry {
        ToolRegistry(
            tools: agentTools(
                context: context,
                embeddingClient: embeddingClient,
                index: index,
                ftsSearch: ftsSearch
            )
        )
    }
}
