import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData

/// Minimal composition graph for the AI Foundation layer (sub-project 1).
/// Wires ContextAssembler, ProposalCoordinator, and a SkillRunner factory
/// from injected dependencies — additive; does not alter AgentComposition.make.
@MainActor
public struct FoundationComposition {
    public let assembler: ContextAssembler
    public let proposalCoordinator: ProposalCoordinator

    public init(
        agentContext: AgentContext,
        retriever: any RagRetriever,
        dispatcher: ToolDispatcher,
        inference: any SkillInference
    ) {
        self.assembler = ContextAssembler(agentContext: agentContext, retriever: retriever)
        self.proposalCoordinator = ProposalCoordinator(dispatcher: dispatcher)
        self._inference = inference
    }

    private let _inference: any SkillInference

    /// Returns a ready-to-use SkillRunner backed by this composition's assembler
    /// and the inference seam provided at construction time.
    public func makeRunner() -> SkillRunner {
        SkillRunner(inference: _inference, assembler: assembler)
    }

    /// Returns a SkillRunner backed by this composition's assembler
    /// and a caller-supplied inference seam (e.g. ScriptedSkillInference in tests).
    public func makeRunner(inference: any SkillInference) -> SkillRunner {
        SkillRunner(inference: inference, assembler: assembler)
    }

    // MARK: - Testing factory

    /// Builds a FoundationComposition entirely from in-memory pieces.
    /// Suitable for unit tests — no real MLX model, no filesystem access.
    public static func makeForTesting() throws -> FoundationComposition {
        // Full schema matching ProposalHarness.make() so AgentAuditLog inserts
        // (from ToolDispatcher.dispatch) succeed against the shared container.
        let schema = Schema([
            AgentAuditLog.self,
            Link.self,
            DebugItem.self,
            QuotaLog.self,
            TaskItem.self,
            Project.self,
            Section.self,
            Comment.self,
            Note.self,
            ScheduledBlock.self,
            Label.self,
            Person.self,
            Cycle.self,
            ActivityEntry.self,
            SavedFilter.self,
            Organization.self,
            ProjectKeyDate.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let repository = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { now }
        )
        let agentContext = AgentContext(
            modelContext: ModelContextRef(context),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { now }
        )

        let registry = ToolRegistry(tools: [TasksCreateTool()])
        let dispatcher = ToolDispatcher(
            registry: registry,
            modelContext: context,
            agentContext: agentContext
        )

        return FoundationComposition(
            agentContext: agentContext,
            retriever: EmptyRetriever(),
            dispatcher: dispatcher,
            inference: NoopSkillInference()
        )
    }
}

// MARK: - Private stubs (Sources-safe; no test types)

private struct EmptyRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] { [] }
}

private struct NoopSkillInference: SkillInference {
    func generate(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "", providerUsed: .mlx)
    }
}
