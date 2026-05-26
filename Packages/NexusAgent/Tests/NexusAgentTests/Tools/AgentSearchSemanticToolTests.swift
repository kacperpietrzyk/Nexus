import CryptoKit
import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
struct AgentSearchSemanticToolTests {
    @Test
    func semanticSearchReturnsRagHitsForIndexedTask() async throws {
        let harness = try SearchToolHarness.make()
        let task = TaskItem(title: "Buy oat milk", body: "Pick up barista oats")
        harness.modelContext.insert(task)
        try harness.modelContext.save()
        try harness.index.upsert(id: task.id, vector: FakeSearchEmbeddingClient.vector("oat"))
        let tool = harness.tool()

        let hits = try await tool.retrieve(query: "oat", scope: "global", limit: 5)
        let output = try await tool.call(
            args: .object([
                "query": .string("oat"),
                "limit": .int(5),
            ]),
            context: harness.agentContext
        )

        #expect(hits.map(\.itemID) == [task.id])
        #expect(hits.first?.kind == "task")
        #expect(hits.first?.title == "Buy oat milk")
        #expect(output.objectValue?["hits"]?.arrayValue?.isEmpty == false)
    }

    @Test
    func hybridRRFHonorsCombinedFTSAndVectorRanking() async throws {
        let harness = try SearchToolHarness.make()
        let vectorTask = TaskItem(title: "Vector match")
        let hybridTask = TaskItem(title: "Hybrid match")
        harness.modelContext.insert(vectorTask)
        harness.modelContext.insert(hybridTask)
        try harness.modelContext.save()
        try harness.index.upsert(id: vectorTask.id, vector: FakeSearchEmbeddingClient.vector("query"))
        try harness.index.upsert(id: hybridTask.id, vector: FakeSearchEmbeddingClient.vector("near-query"))
        let tool = harness.tool(ftsSearch: FakeFTSSearch(results: [hybridTask.id]))

        let hits = try await tool.retrieve(query: "query", scope: "global", limit: 2)

        #expect(hits.map(\.itemID) == [hybridTask.id, vectorTask.id])
    }

    @Test
    func degradedTrueWhenManyItemsHaveFewEmbeddings() async throws {
        let harness = try SearchToolHarness.make()
        for index in 0..<10 {
            harness.modelContext.insert(TaskItem(title: "Task \(index)"))
        }
        try harness.modelContext.save()
        let tool = harness.tool()

        let output = try await tool.call(
            args: .object([
                "query": .string("task"),
                "limit": .int(5),
            ]),
            context: harness.agentContext
        )

        #expect(output.objectValue?["degraded"] == .bool(true))
    }

    @Test
    func staleEmbeddingsDoNotCountAsLiveCoverage() async throws {
        let harness = try SearchToolHarness.make()
        for index in 0..<10 {
            harness.modelContext.insert(TaskItem(title: "Task \(index)"))
            harness.modelContext.insert(
                ItemEmbedding(
                    itemID: UUID(),
                    kind: "task",
                    vector: FakeSearchEmbeddingClient.vector("stale \(index)"),
                    textHash: FakeSearchEmbeddingClient.hash("stale \(index)"),
                    vectorDimension: 4
                )
            )
        }
        try harness.modelContext.save()
        let tool = harness.tool()

        let output = try await tool.call(
            args: .object([
                "query": .string("task"),
                "limit": .int(5),
            ]),
            context: harness.agentContext
        )

        #expect(output.objectValue?["degraded"] == .bool(true))
        #expect(degradationReasons(in: output).contains("embedding_index_incomplete"))
    }

    @Test
    func fallsBackToFTSWhenVectorSearchUnavailable() async throws {
        let harness = try SearchToolHarness.make()
        let task = TaskItem(title: "FTS fallback task")
        harness.modelContext.insert(task)
        try harness.modelContext.save()
        let tool = harness.tool(
            embeddingClient: FailingEmbeddingClient(),
            ftsSearch: FakeFTSSearch(results: [task.id])
        )

        let output = try await tool.call(
            args: .object([
                "query": .string("fallback"),
                "limit": .int(5),
            ]),
            context: harness.agentContext
        )

        let hits = hitObjects(in: output)
        #expect(hits.first?["itemID"]?.stringValue == task.id.uuidString)
        #expect(output.objectValue?["degraded"] == .bool(true))
        #expect(degradationReasons(in: output).contains("vector_search_unavailable"))
    }

    @Test
    func fallsBackToFTSWhenVectorIndexRejectsQuery() async throws {
        let harness = try SearchToolHarness.make()
        let task = TaskItem(title: "FTS fallback after vector error")
        harness.modelContext.insert(task)
        try harness.modelContext.save()
        let tool = harness.tool(
            embeddingClient: WrongDimensionEmbeddingClient(),
            ftsSearch: FakeFTSSearch(results: [task.id])
        )

        let output = try await tool.call(
            args: .object([
                "query": .string("fallback"),
                "limit": .int(5),
            ]),
            context: harness.agentContext
        )

        let hits = hitObjects(in: output)
        #expect(hits.first?["itemID"]?.stringValue == task.id.uuidString)
        #expect(output.objectValue?["degraded"] == .bool(true))
        #expect(degradationReasons(in: output).contains("vector_search_unavailable"))
    }

    @Test
    func kindFilterStillReturnsLowerRankedMatchingCandidate() async throws {
        let harness = try SearchToolHarness.make()
        var wrongKindIDs = [UUID]()
        for index in 0..<260 {
            let memory = AgentMemoryEntry(
                scope: "global",
                key: "memory-\(index)",
                content: "Wrong kind"
            )
            harness.modelContext.insert(memory)
            wrongKindIDs.append(memory.id)
        }
        let task = TaskItem(title: "Lower ranked task")
        harness.modelContext.insert(task)
        try harness.modelContext.save()
        let tool = harness.tool(ftsSearch: FakeFTSSearch(results: wrongKindIDs + [task.id]))

        let output = try await tool.call(
            args: .object([
                "query": .string("ranked"),
                "kinds": .array([.string("task")]),
                "limit": .int(1),
            ]),
            context: harness.agentContext
        )

        let hits = hitObjects(in: output)
        #expect(hits.map { $0["itemID"]?.stringValue } == [task.id.uuidString])
        #expect(hits.first?["kind"] == .string("task"))
    }

    @Test
    func validatesEmptyQueryLimitAndKinds() async throws {
        let harness = try SearchToolHarness.make()
        let tool = harness.tool()

        await #expect(throws: AgentError.validation("query cannot be empty")) {
            try await tool.call(
                args: .object(["query": .string("   ")]),
                context: harness.agentContext
            )
        }

        await #expect(throws: AgentError.validation("limit must be between 1 and 50")) {
            try await tool.call(
                args: .object([
                    "query": .string("x"),
                    "limit": .int(51),
                ]),
                context: harness.agentContext
            )
        }

        await #expect(throws: AgentError.validation("Unknown kind: bogus")) {
            try await tool.call(
                args: .object([
                    "query": .string("x"),
                    "kinds": .array([.string("bogus")]),
                ]),
                context: harness.agentContext
            )
        }
    }

    @Test
    func hydratesAgentMemoryEntry() async throws {
        let harness = try SearchToolHarness.make()
        let memory = AgentMemoryEntry(
            scope: "global",
            key: "shopping",
            content: "Prefers oat milk"
        )
        harness.modelContext.insert(memory)
        try harness.modelContext.save()
        try harness.index.upsert(id: memory.id, vector: FakeSearchEmbeddingClient.vector("oat"))
        let tool = harness.tool()

        let hits = try await tool.retrieve(query: "oat", scope: "global", limit: 5)

        #expect(hits.map(\.itemID) == [memory.id])
        #expect(hits.first?.kind == "agentMemory")
        #expect(hits.first?.title == "global/shopping")
        #expect(hits.first?.snippet == "Prefers oat milk")
    }

    private func hitObjects(in output: JSONValue) -> [[String: JSONValue]] {
        output.objectValue?["hits"]?.arrayValue?.compactMap(\.objectValue) ?? []
    }

    private func degradationReasons(in output: JSONValue) -> [String] {
        output.objectValue?["degradationReasons"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }
}

private struct SearchToolHarness {
    let modelContext: ModelContext
    let index: SqliteVecIndex
    let agentContext: AgentContext

    @MainActor
    static func make() throws -> SearchToolHarness {
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
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)
        let repository = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let agentContext = AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return SearchToolHarness(
            modelContext: modelContext,
            index: try SqliteVecIndex.inMemory(dimension: 4),
            agentContext: agentContext
        )
    }

    @MainActor
    func tool(
        embeddingClient: any EmbeddingClient = FakeSearchEmbeddingClient(),
        ftsSearch: any FTSSearch = NoopFTSSearch()
    ) -> AgentSearchSemanticTool {
        AgentSearchSemanticTool(
            embeddingClient: embeddingClient,
            index: index,
            ftsSearch: ftsSearch,
            context: modelContext
        )
    }
}

private struct FakeFTSSearch: FTSSearch {
    let results: [UUID]

    func search(query: String, limit: Int) async throws -> [UUID] {
        Array(results.prefix(limit))
    }
}

private final class FakeSearchEmbeddingClient: EmbeddingClient, @unchecked Sendable {
    func embed(_ text: String) async throws -> NLEmbeddingResult {
        NLEmbeddingResult(
            vector: Self.vector(text),
            detectedLanguage: "test",
            textHash: Self.hash(text),
            dimension: 4
        )
    }

    static func vector(_ text: String) -> Data {
        let floats: [Float]
        switch text {
        case "query":
            floats = [1, 0, 0, 0]
        case "near-query":
            floats = [0.8, 0.2, 0, 0]
        default:
            let seed = Float(abs(text.hashValue % 1000)) / 1000
            floats = [seed, seed + 0.01, seed + 0.02, seed + 0.03]
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct FailingEmbeddingClient: EmbeddingClient {
    func embed(_ text: String) async throws -> NLEmbeddingResult {
        throw AgentError.internalError("embedding unavailable")
    }
}

private struct WrongDimensionEmbeddingClient: EmbeddingClient {
    func embed(_ text: String) async throws -> NLEmbeddingResult {
        let floats: [Float] = [1, 2]
        return NLEmbeddingResult(
            vector: floats.withUnsafeBufferPointer { Data(buffer: $0) },
            detectedLanguage: "test",
            textHash: "wrong-dimension",
            dimension: 2
        )
    }
}
