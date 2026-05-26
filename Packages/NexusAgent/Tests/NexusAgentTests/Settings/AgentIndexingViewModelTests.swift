import CryptoKit
import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct AgentIndexingViewModelTests {
    @Test func coverageIgnoresOrphanAndDeletedEmbeddings() throws {
        let harness = try AgentIndexingHarness.make()
        let indexedTask = TaskItem(title: "Indexed")
        let unindexedTask = TaskItem(title: "Unindexed")
        let deletedTask = TaskItem(title: "Deleted")
        deletedTask.deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let memory = AgentMemoryEntry(key: "preference", content: "Prefers short briefs")
        let deletedMemory = AgentMemoryEntry(
            key: "old-preference",
            content: "Ignore",
            deletedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        harness.context.insert(indexedTask)
        harness.context.insert(unindexedTask)
        harness.context.insert(deletedTask)
        harness.context.insert(memory)
        harness.context.insert(deletedMemory)
        harness.context.insert(
            ItemEmbedding(
                itemID: indexedTask.id,
                kind: ItemKind.task.rawValue,
                vector: AgentIndexingEmbeddingClient.vector(for: indexedTask.searchableText),
                textHash: AgentIndexingEmbeddingClient.hash(indexedTask.searchableText),
                language: "test",
                vectorDimension: 4
            )
        )
        harness.context.insert(
            ItemEmbedding(
                itemID: deletedTask.id,
                kind: ItemKind.task.rawValue,
                vector: AgentIndexingEmbeddingClient.vector(for: deletedTask.searchableText),
                textHash: AgentIndexingEmbeddingClient.hash(deletedTask.searchableText),
                language: "test",
                vectorDimension: 4
            )
        )
        harness.context.insert(
            ItemEmbedding(
                itemID: UUID(),
                kind: ItemKind.task.rawValue,
                vector: AgentIndexingEmbeddingClient.vector(for: "orphan"),
                textHash: AgentIndexingEmbeddingClient.hash("orphan"),
                language: "test",
                vectorDimension: 4
            )
        )
        try harness.context.save()

        let viewModel = AgentIndexingViewModel(
            context: harness.context,
            backfill: harness.backfill
        )
        viewModel.refresh()

        #expect(viewModel.coverage.indexed == 1)
        #expect(viewModel.coverage.total == 3)
        #expect(viewModel.coverage.ratio == 1.0 / 3.0)
    }

    @Test func rebuildStoresProgressAndRefreshesCoverage() async throws {
        let harness = try AgentIndexingHarness.make()
        let task = TaskItem(title: "Index from rebuild")
        harness.context.insert(task)
        try harness.context.save()

        let viewModel = AgentIndexingViewModel(
            context: harness.context,
            backfill: harness.backfill
        )
        await viewModel.rebuild()

        #expect(viewModel.lastProgress == BackfillProgress(processed: 1, skipped: 0, total: 1))
        #expect(viewModel.coverage.indexed == 1)
        #expect(viewModel.coverage.total == 1)
        #expect(viewModel.coverage.ratio == 1.0)
    }
}

private struct AgentIndexingHarness {
    let context: ModelContext
    let backfill: BackfillEmbeddingsJob

    @MainActor
    static func make() throws -> AgentIndexingHarness {
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
        let context = ModelContext(container)
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: AgentIndexingEmbeddingClient(),
            index: try SqliteVecIndex.inMemory(dimension: 4),
            context: context,
            debounce: .milliseconds(0)
        )
        return AgentIndexingHarness(
            context: context,
            backfill: BackfillEmbeddingsJob(context: context, dispatcher: dispatcher)
        )
    }
}

private final class AgentIndexingEmbeddingClient: EmbeddingClient, @unchecked Sendable {
    func embed(_ text: String) async throws -> NLEmbeddingResult {
        NLEmbeddingResult(
            vector: Self.vector(for: text),
            detectedLanguage: "test",
            textHash: Self.hash(text),
            dimension: 4
        )
    }

    static func vector(for text: String) -> Data {
        let seed = Float(abs(text.hashValue % 1_000)) / 1_000
        let floats: [Float] = [seed, seed + 0.01, seed + 0.02, seed + 0.03]
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
