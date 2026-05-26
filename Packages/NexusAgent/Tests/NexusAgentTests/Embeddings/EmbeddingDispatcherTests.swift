import CryptoKit
import Foundation
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct EmbeddingDispatcherTests {
    @Test func debounceCreatesOneItemEmbeddingForRepeatedEnqueues() async throws {
        let context = try AgentTestSupport.makeContext()
        let client = FakeEmbeddingClient()
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: client,
            index: try SqliteVecIndex.inMemory(dimension: 4),
            context: context,
            debounce: .milliseconds(200)
        )
        let id = UUID()

        for value in ["buy milk 1", "buy milk 2", "buy milk 3", "buy milk 4", "buy milk 5"] {
            await dispatcher.enqueue(itemID: id, kind: "task", text: value)
        }
        try await Task.sleep(for: .milliseconds(360))

        let embeddings = try fetchEmbeddings(context, itemID: id)
        #expect(embeddings.count == 1)
        #expect(embeddings.first?.textHash == FakeEmbeddingClient.hash("buy milk 5"))
        #expect(client.calls == ["buy milk 5"])
        #expect(await dispatcher.pendingCount() == 0)
    }

    @Test func skipsUnchangedTextWithoutTouchingStoredEmbedding() async throws {
        let context = try AgentTestSupport.makeContext()
        let client = FakeEmbeddingClient()
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: client,
            index: try SqliteVecIndex.inMemory(dimension: 4),
            context: context,
            debounce: .milliseconds(10)
        )
        let id = UUID()

        await dispatcher.flush(itemID: id, kind: "task", text: "same text")
        let initial = try #require(fetchEmbeddings(context, itemID: id).first)

        await dispatcher.flush(itemID: id, kind: "task", text: "same text")
        let second = try #require(fetchEmbeddings(context, itemID: id).first)

        #expect(initial.updatedAt == second.updatedAt)
        #expect(second.vector == FakeEmbeddingClient.vector(for: "same text"))
        #expect(client.calls == ["same text", "same text"])
    }

    @Test func unchangedTextRehydratesEmptyVectorIndexWithoutChangingUpdatedAt() async throws {
        let context = try AgentTestSupport.makeContext()
        let client = FakeEmbeddingClient()
        let index = try SqliteVecIndex.inMemory(dimension: 4)
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: client,
            index: index,
            context: context,
            debounce: .milliseconds(10)
        )
        let id = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(
            ItemEmbedding(
                itemID: id,
                kind: "task",
                vector: FakeEmbeddingClient.vector(for: "same text"),
                textHash: FakeEmbeddingClient.hash("same text"),
                language: "test",
                vectorDimension: 4,
                updatedAt: updatedAt
            )
        )
        try context.save()

        await dispatcher.enqueue(itemID: id, kind: "task", text: "same text")
        try await Task.sleep(for: .milliseconds(120))

        let embeddings = try fetchEmbeddings(context, itemID: id)
        #expect(embeddings.first?.updatedAt == updatedAt)

        let hits = try index.search(query: FakeEmbeddingClient.vector(for: "same text"), limit: 1)
        #expect(hits.first?.itemID == id)
    }

    @Test func updatesChangedTextInStoreAndVectorIndex() async throws {
        let context = try AgentTestSupport.makeContext()
        let client = FakeEmbeddingClient()
        let index = try SqliteVecIndex.inMemory(dimension: 4)
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: client,
            index: index,
            context: context,
            debounce: .milliseconds(10)
        )
        let id = UUID()

        await dispatcher.flush(itemID: id, kind: "task", text: "old text")
        let initial = try #require(fetchEmbeddings(context, itemID: id).first)
        let initialUpdatedAt = initial.updatedAt

        await dispatcher.flush(itemID: id, kind: "task", text: "changed text")
        let updated = try #require(fetchEmbeddings(context, itemID: id).first)

        #expect(updated.textHash == FakeEmbeddingClient.hash("changed text"))
        #expect(updated.vector == FakeEmbeddingClient.vector(for: "changed text"))
        #expect(updated.updatedAt > initialUpdatedAt)

        let hits = try index.search(query: FakeEmbeddingClient.vector(for: "changed text"), limit: 1)
        #expect(hits.first?.itemID == id)
    }

    @Test func staleCancelledWorkCannotOverwriteNewerEmbedding() async throws {
        let context = try AgentTestSupport.makeContext()
        let client = ControlledEmbeddingClient()
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: client,
            index: try SqliteVecIndex.inMemory(dimension: 4),
            context: context,
            debounce: .milliseconds(0)
        )
        let id = UUID()

        await dispatcher.enqueue(itemID: id, kind: "task", text: "old text")
        try await client.waitUntilPending("old text")

        await dispatcher.enqueue(itemID: id, kind: "task", text: "new text")
        try await client.waitUntilPending("new text")

        client.resume("new text")
        try await Task.sleep(for: .milliseconds(40))
        client.resume("old text")
        try await Task.sleep(for: .milliseconds(80))

        let stored = try #require(fetchEmbeddings(context, itemID: id).first)
        #expect(stored.textHash == ControlledEmbeddingClient.hash("new text"))
        #expect(stored.vector == ControlledEmbeddingClient.vector(for: "new text"))
        #expect(await dispatcher.pendingCount() == 0)
    }

    @Test func staleWorkAtSaveBoundaryCannotPersistAfterNewerEnqueue() async throws {
        let context = try AgentTestSupport.makeContext()
        let barrier = SaveBoundaryBarrier(blockedText: "old text")
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: FakeEmbeddingClient(),
            index: try SqliteVecIndex.inMemory(dimension: 4),
            context: context,
            debounce: .milliseconds(0),
            beforeSave: { _, text in
                await barrier.pauseIfNeeded(text)
            }
        )
        let id = UUID()

        await dispatcher.enqueue(itemID: id, kind: "task", text: "old text")
        try await barrier.waitUntilPaused()

        await dispatcher.enqueue(itemID: id, kind: "task", text: "new text")
        await barrier.resume()
        try await Task.sleep(for: .milliseconds(140))

        let stored = try #require(fetchEmbeddings(context, itemID: id).first)
        #expect(stored.textHash == FakeEmbeddingClient.hash("new text"))
        #expect(stored.vector == FakeEmbeddingClient.vector(for: "new text"))
        #expect(await dispatcher.pendingCount() == 0)
    }

    @Test func flushEmbedsImmediatelyForTestsAndBackfill() async throws {
        let context = try AgentTestSupport.makeContext()
        let dispatcher = EmbeddingDispatcher(
            embeddingClient: FakeEmbeddingClient(),
            index: try SqliteVecIndex.inMemory(dimension: 4),
            context: context,
            debounce: .seconds(5)
        )
        let id = UUID()

        await dispatcher.flush(itemID: id, kind: "task", text: "now")

        let embeddings = try fetchEmbeddings(context, itemID: id)
        #expect(embeddings.count == 1)
        #expect(embeddings.first?.textHash == FakeEmbeddingClient.hash("now"))
    }
}

private final class FakeEmbeddingClient: EmbeddingClient, @unchecked Sendable {
    private(set) var calls = [String]()

    func embed(_ text: String) async throws -> NLEmbeddingResult {
        calls.append(text)
        return NLEmbeddingResult(
            vector: Self.vector(for: text),
            detectedLanguage: "test",
            textHash: Self.hash(text),
            dimension: 4
        )
    }

    static func vector(for text: String) -> Data {
        let seed = Float(abs(text.hashValue % 1000)) / 1000
        let floats: [Float] = [seed, seed + 0.01, seed + 0.02, seed + 0.03]
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private final class ControlledEmbeddingClient: EmbeddingClient, @unchecked Sendable {
    private var continuations = [String: CheckedContinuation<Void, Never>]()
    private let lock = NSLock()

    func embed(_ text: String) async throws -> NLEmbeddingResult {
        await withCheckedContinuation { continuation in
            lock.withLock {
                continuations[text] = continuation
            }
        }

        return NLEmbeddingResult(
            vector: Self.vector(for: text),
            detectedLanguage: "test",
            textHash: Self.hash(text),
            dimension: 4
        )
    }

    func waitUntilPending(_ text: String) async throws {
        for _ in 0..<100 {
            if lock.withLock({ continuations[text] != nil }) {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for pending embedding: \(text)")
    }

    func resume(_ text: String) {
        let continuation = lock.withLock {
            continuations.removeValue(forKey: text)
        }
        continuation?.resume()
    }

    static func vector(for text: String) -> Data {
        FakeEmbeddingClient.vector(for: text)
    }

    static func hash(_ text: String) -> String {
        FakeEmbeddingClient.hash(text)
    }
}

private actor SaveBoundaryBarrier {
    private enum BarrierError: Error {
        case timedOut
    }

    private let blockedText: String
    private var continuation: CheckedContinuation<Void, Never>?
    private var paused = false

    init(blockedText: String) {
        self.blockedText = blockedText
    }

    func pauseIfNeeded(_ text: String) async {
        guard text == blockedText else {
            return
        }

        paused = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilPaused() async throws {
        for _ in 0..<100 {
            if paused {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw BarrierError.timedOut
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private func fetchEmbeddings(_ context: ModelContext, itemID: UUID) throws -> [ItemEmbedding] {
    try context.fetch(
        FetchDescriptor<ItemEmbedding>(
            predicate: #Predicate { $0.itemID == itemID },
            sortBy: [SortDescriptor(\.updatedAt)]
        )
    )
}
