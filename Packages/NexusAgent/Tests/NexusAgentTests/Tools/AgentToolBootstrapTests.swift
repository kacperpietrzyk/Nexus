import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct AgentToolBootstrapTests {
    @Test func makesAllAgentTools() throws {
        let context = try makeContext()
        let tools = AgentToolBootstrap.agentTools(
            context: context,
            embeddingClient: BootstrapEmbeddingClient(),
            index: try SqliteVecIndex.inMemory(dimension: 4),
            ftsSearch: NoopFTSSearch()
        )
        let names = tools.map(\.name)

        #expect(
            names == [
                "agent.remember",
                "agent.forget",
                "agent.recall",
                "agent.link_items",
                "agent.unlink_items",
                "agent.noop",
                "agent.activity_log",
                "agent.search_semantic",
            ])
    }

    @Test func makesRegistryWithoutDuplicateNames() throws {
        let context = try makeContext()
        let registry = AgentToolBootstrap.makeRegistry(
            context: context,
            embeddingClient: BootstrapEmbeddingClient(),
            index: try SqliteVecIndex.inMemory(dimension: 4),
            ftsSearch: NoopFTSSearch()
        )
        let names = registry.tools.map(\.name)

        #expect(Set(names).count == names.count)
        #expect(registry.tool(named: "agent.remember") != nil)
        #expect(registry.tool(named: "agent.forget") != nil)
        #expect(registry.tool(named: "agent.recall") != nil)
        #expect(registry.tool(named: "agent.link_items") != nil)
        #expect(registry.tool(named: "agent.unlink_items") != nil)
        #expect(registry.tool(named: "agent.noop") != nil)
        #expect(registry.tool(named: "agent.activity_log") != nil)
        #expect(registry.tool(named: "agent.search_semantic") != nil)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            AgentAuditLog.self,
            AgentMemoryEntry.self,
            AgentMessage.self,
            AgentSchedule.self,
            AgentThread.self,
            DebugItem.self,
            ItemEmbedding.self,
            Link.self,
            QuotaLog.self,
            TaskItem.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContext(ModelContainer(for: schema, configurations: [configuration]))
    }
}

private struct BootstrapEmbeddingClient: EmbeddingClient {
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
