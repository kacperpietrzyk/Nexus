import CryptoKit
import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct BackfillEmbeddingsJobTests {
    @Test func enqueuesMissingTasksAndMemories() async throws {
        let harness = try BackfillHarness.make()
        let task = TaskItem(title: "Buy milk", body: "Pick up oat milk")
        let memory = AgentMemoryEntry(
            scope: "global",
            key: "preference",
            content: "Prefers oat milk"
        )
        harness.context.insert(task)
        harness.context.insert(memory)
        try harness.context.save()

        let progress = try await BackfillEmbeddingsJob(
            context: harness.context,
            dispatcher: harness.dispatcher,
            index: harness.index
        ).run()
        try await harness.waitForQueueDrain()

        #expect(progress == BackfillProgress(processed: 2, skipped: 0, total: 2))
        #expect(try harness.embeddingCount() == 2)
        #expect(
            Set(harness.client.calls)
                == Set([
                    task.searchableText,
                    memory.searchableText,
                ]))
    }

    @Test func skipsAlreadyEmbeddedItems() async throws {
        let harness = try BackfillHarness.make()
        let task = TaskItem(title: "Already indexed")
        harness.context.insert(task)
        harness.context.insert(
            ItemEmbedding(
                itemID: task.id,
                kind: ItemKind.task.rawValue,
                vector: FakeBackfillEmbeddingClient.vector(for: task.searchableText),
                textHash: FakeBackfillEmbeddingClient.hash(task.searchableText),
                language: "test",
                vectorDimension: 4
            )
        )
        try harness.context.save()

        let progress = try await BackfillEmbeddingsJob(
            context: harness.context,
            dispatcher: harness.dispatcher,
            index: harness.index
        ).run()
        try await harness.waitForQueueDrain()

        #expect(progress == BackfillProgress(processed: 0, skipped: 1, total: 1))
        #expect(try harness.embeddingCount() == 1)
        #expect(harness.client.calls == [task.searchableText])
        #expect(await harness.dispatcher.pendingCount() == 0)
    }

    @Test func ignoresDeletedTasksAndMemories() async throws {
        let harness = try BackfillHarness.make()
        let task = TaskItem(title: "Deleted task")
        task.deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let memory = AgentMemoryEntry(
            scope: "global",
            key: "deleted-memory",
            content: "Do not index",
            deletedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        harness.context.insert(task)
        harness.context.insert(memory)
        try harness.context.save()

        let progress = try await BackfillEmbeddingsJob(
            context: harness.context,
            dispatcher: harness.dispatcher,
            index: harness.index
        ).run()

        #expect(progress == BackfillProgress(processed: 0, skipped: 0, total: 0))
        #expect(try harness.embeddingCount() == 0)
        #expect(harness.client.calls.isEmpty)
    }

    @Test func existingUnchangedEmbeddingRehydratesEmptyVectorIndex() async throws {
        let harness = try BackfillHarness.make()
        let task = TaskItem(title: "Indexed task", body: "Same text")
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        harness.context.insert(task)
        harness.context.insert(
            ItemEmbedding(
                itemID: task.id,
                kind: ItemKind.task.rawValue,
                vector: FakeBackfillEmbeddingClient.vector(for: task.searchableText),
                textHash: FakeBackfillEmbeddingClient.hash(task.searchableText),
                language: "test",
                vectorDimension: 4,
                updatedAt: updatedAt
            )
        )
        try harness.context.save()

        let progress = try await BackfillEmbeddingsJob(
            context: harness.context,
            dispatcher: harness.dispatcher,
            index: harness.index
        ).run()
        try await harness.waitForQueueDrain()

        let storedEmbedding = try harness.embedding(itemID: task.id)
        let embedding = try #require(storedEmbedding)
        let hits = try harness.index.search(
            query: FakeBackfillEmbeddingClient.vector(for: task.searchableText),
            limit: 1
        )
        #expect(progress == BackfillProgress(processed: 0, skipped: 1, total: 1))
        #expect(embedding.updatedAt == updatedAt)
        #expect(hits.first?.itemID == task.id)
    }

    @Test func existingChangedEmbeddingRefreshesStoreAndVectorIndex() async throws {
        let harness = try BackfillHarness.make()
        let task = TaskItem(title: "Indexed task", body: "New text")
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        harness.context.insert(task)
        harness.context.insert(
            ItemEmbedding(
                itemID: task.id,
                kind: ItemKind.task.rawValue,
                vector: FakeBackfillEmbeddingClient.vector(for: "old text"),
                textHash: FakeBackfillEmbeddingClient.hash("old text"),
                language: "test",
                vectorDimension: 4,
                updatedAt: updatedAt
            )
        )
        try harness.context.save()

        let progress = try await BackfillEmbeddingsJob(
            context: harness.context,
            dispatcher: harness.dispatcher,
            index: harness.index
        ).run()
        try await harness.waitForQueueDrain()

        let storedEmbedding = try harness.embedding(itemID: task.id)
        let embedding = try #require(storedEmbedding)
        let hits = try harness.index.search(
            query: FakeBackfillEmbeddingClient.vector(for: task.searchableText),
            limit: 1
        )
        #expect(progress == BackfillProgress(processed: 0, skipped: 1, total: 1))
        #expect(embedding.textHash == FakeBackfillEmbeddingClient.hash(task.searchableText))
        #expect(embedding.vector == FakeBackfillEmbeddingClient.vector(for: task.searchableText))
        #expect(embedding.updatedAt > updatedAt)
        #expect(hits.first?.itemID == task.id)
    }

    /// Characterization (perf/today-data-scaling): the ItemEmbedding table is now
    /// fetched ONCE and reused for both the already-embedded skip check and stale
    /// detection. Seed a stale embedding AND an already-embedded live task in the
    /// same run, plus a brand-new task, and assert the single-fetch path produces
    /// the same enqueue counts and the same stale removal as two separate fetches.
    @Test func singleFetchSkipsEmbeddedProcessesNewAndRemovesStale() async throws {
        let harness = try BackfillHarness.make()

        let embeddedTask = TaskItem(title: "Already embedded")
        let newTask = TaskItem(title: "Brand new")
        harness.context.insert(embeddedTask)
        harness.context.insert(newTask)
        harness.context.insert(
            ItemEmbedding(
                itemID: embeddedTask.id,
                kind: ItemKind.task.rawValue,
                vector: FakeBackfillEmbeddingClient.vector(for: embeddedTask.searchableText),
                textHash: FakeBackfillEmbeddingClient.hash(embeddedTask.searchableText),
                language: "test",
                vectorDimension: 4
            )
        )

        let staleID = UUID()
        let staleVector = FakeBackfillEmbeddingClient.vector(for: "stale text")
        harness.context.insert(
            ItemEmbedding(
                itemID: staleID,
                kind: ItemKind.task.rawValue,
                vector: staleVector,
                textHash: FakeBackfillEmbeddingClient.hash("stale text"),
                language: "test",
                vectorDimension: 4
            )
        )
        try harness.index.upsert(id: staleID, vector: staleVector)
        try harness.context.save()

        let progress = try await BackfillEmbeddingsJob(
            context: harness.context,
            dispatcher: harness.dispatcher,
            index: harness.index
        ).run()
        try await harness.waitForQueueDrain()

        // 1 new task processed, 1 already-embedded task skipped, total = 2 live tasks.
        #expect(progress == BackfillProgress(processed: 1, skipped: 1, total: 2))
        // Both live tasks were enqueued; the stale (non-live) id was not.
        #expect(
            Set(harness.client.calls)
                == Set([embeddedTask.searchableText, newTask.searchableText]))
        // Stale embedding removed from the store; live embeddings remain.
        // (Index-search is not asserted here: the two enqueued live embeddings are
        // added to the same index, so a nearest-neighbour query is not a clean
        // stale-removal signal — see removesEmbeddingsForItemsMissingFromLiveStore
        // for the index-eviction characterization with no live embeddings present.)
        #expect(try harness.embedding(itemID: staleID) == nil)
        #expect(try harness.embedding(itemID: embeddedTask.id) != nil)
    }

    @Test func removesEmbeddingsForItemsMissingFromLiveStore() async throws {
        let harness = try BackfillHarness.make()
        let staleID = UUID()
        let staleVector = FakeBackfillEmbeddingClient.vector(for: "stale text")
        harness.context.insert(
            ItemEmbedding(
                itemID: staleID,
                kind: ItemKind.task.rawValue,
                vector: staleVector,
                textHash: FakeBackfillEmbeddingClient.hash("stale text"),
                language: "test",
                vectorDimension: 4
            )
        )
        try harness.index.upsert(id: staleID, vector: staleVector)
        try harness.context.save()

        let progress = try await BackfillEmbeddingsJob(
            context: harness.context,
            dispatcher: harness.dispatcher,
            index: harness.index
        ).run()

        #expect(progress == BackfillProgress(processed: 0, skipped: 0, total: 0))
        #expect(try harness.embeddingCount() == 0)
        #expect(try harness.index.search(query: staleVector, limit: 1).isEmpty)
    }
}

private struct BackfillHarness {
    let context: ModelContext
    let dispatcher: EmbeddingDispatcher
    let index: SqliteVecIndex
    let client: FakeBackfillEmbeddingClient

    @MainActor
    static func make() throws -> BackfillHarness {
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
        let client = FakeBackfillEmbeddingClient()
        let index = try SqliteVecIndex.inMemory(dimension: 4)
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: client,
            index: index,
            context: context,
            debounce: .milliseconds(0)
        )
        return BackfillHarness(
            context: context,
            dispatcher: dispatcher,
            index: index,
            client: client
        )
    }

    @MainActor
    func waitForQueueDrain() async throws {
        for _ in 0..<100 {
            if await dispatcher.pendingCount() == 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for embedding queue to drain")
    }

    @MainActor
    func embeddingCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<ItemEmbedding>())
    }

    @MainActor
    func embedding(itemID: UUID) throws -> ItemEmbedding? {
        let descriptor = FetchDescriptor<ItemEmbedding>(
            predicate: #Predicate { $0.itemID == itemID }
        )
        return try context.fetch(descriptor).first
    }
}

private final class FakeBackfillEmbeddingClient: EmbeddingClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls = [String]()

    var calls: [String] {
        lock.withLock { recordedCalls }
    }

    func embed(_ text: String) async throws -> NLEmbeddingResult {
        lock.withLock {
            recordedCalls.append(text)
        }
        return NLEmbeddingResult(
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
