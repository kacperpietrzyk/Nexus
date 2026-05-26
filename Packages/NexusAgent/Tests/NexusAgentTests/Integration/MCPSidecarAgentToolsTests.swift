import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct MCPSidecarAgentToolsTests {
    @Test func sidecarRegistryExposesAgentTools() throws {
        let harness = try SidecarToolHarness.make()

        let manifestNames = harness.registry.manifest().tools.map(\.name)
        let registryNames = harness.registry.tools.map(\.name)

        #expect(Set(manifestNames) == Set(registryNames))
        #expect(manifestNames.count == registryNames.count)
        #expect(manifestNames.contains("agent.search_semantic"))
        #expect(manifestNames.contains("agent.remember"))
        #expect(manifestNames.contains("agent.activity_log"))
    }

    @Test func sidecarCallsAgentRememberThroughBootstrap() async throws {
        let harness = try SidecarToolHarness.make()
        let tool = try #require(harness.registry.tool(named: "agent.remember"))

        let output = try await tool.call(
            args: .object([
                "scope": .string("global"),
                "key": .string("sidecar-smoke"),
                "content": .string("MCP clients can persist agent memory through bootstrap."),
            ]),
            context: harness.agentContext
        )

        #expect(output.objectValue?["status"] == .string("ok"))
        #expect(
            try harness.store.find(scope: "global", key: "sidecar-smoke")?.content
                == "MCP clients can persist agent memory through bootstrap."
        )
    }
}

@MainActor
private struct SidecarToolHarness {
    let registry: ToolRegistry
    let store: AgentMemoryStore
    let agentContext: AgentContext

    static func make() throws -> SidecarToolHarness {
        let context = try AgentTestSupport.makeContext()
        let repository = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let agentContext = AgentContext(
            modelContext: ModelContextRef(context),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let registry = AgentToolBootstrap.makeRegistry(
            context: context,
            embeddingClient: SidecarEmbeddingClient(),
            index: try SqliteVecIndex.inMemory(dimension: 4),
            ftsSearch: NoopFTSSearch()
        )

        return SidecarToolHarness(
            registry: registry,
            store: AgentMemoryStore(context: context),
            agentContext: agentContext
        )
    }
}

private struct SidecarEmbeddingClient: EmbeddingClient {
    func embed(_ text: String) async throws -> NLEmbeddingResult {
        let floats: [Float] = [1, 0, 0, 0]
        return NLEmbeddingResult(
            vector: floats.withUnsafeBufferPointer { Data(buffer: $0) },
            detectedLanguage: "test",
            textHash: text,
            dimension: 4
        )
    }
}
