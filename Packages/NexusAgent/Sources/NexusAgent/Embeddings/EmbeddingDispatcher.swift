import Foundation
import SwiftData
import os

public protocol EmbeddingClient: Sendable {
    func embed(_ text: String) async throws -> NLEmbeddingResult
}

extension NLEmbeddingClient: EmbeddingClient {
    public func embed(_ text: String) async throws -> NLEmbeddingResult {
        let syncEmbed: (String) throws -> NLEmbeddingResult = embed
        return try syncEmbed(text)
    }
}

public actor EmbeddingDispatcher {
    private struct PendingInput: Sendable {
        let itemID: UUID
        let kind: String
        let text: String
    }

    private struct PendingWork {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct EmbeddingSnapshot: Sendable {
        let vector: Data
        let textHash: String
    }

    private final class GenerationStore: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens = [UUID: UUID]()

        func setCurrent(itemID: UUID, token: UUID) {
            lock.withLock {
                tokens[itemID] = token
            }
        }

        func clearIfCurrent(itemID: UUID, token: UUID) {
            lock.withLock {
                guard tokens[itemID] == token else {
                    return
                }
                tokens.removeValue(forKey: itemID)
            }
        }

        func isCurrent(itemID: UUID, token: UUID) -> Bool {
            lock.withLock {
                tokens[itemID] == token
            }
        }

        func withCurrentToken<T>(itemID: UUID, token: UUID, _ body: () throws -> T) throws -> T? {
            try lock.withLock {
                guard tokens[itemID] == token else {
                    return nil
                }
                return try body()
            }
        }
    }

    // SwiftData ModelContext is main-actor-bound in this package. Keep it behind this helper so the
    // public dispatcher can remain an actor while only Sendable snapshots cross actor boundaries.
    @MainActor
    private final class EmbeddingPersistence {
        private let context: ModelContext
        private let generationStore: GenerationStore
        private let beforeSave: (@MainActor @Sendable (UUID, String) async -> Void)?

        init(
            context: ModelContext,
            generationStore: GenerationStore,
            beforeSave: (@MainActor @Sendable (UUID, String) async -> Void)?
        ) {
            self.context = context
            self.generationStore = generationStore
            self.beforeSave = beforeSave
        }

        func snapshot(itemID: UUID) throws -> EmbeddingSnapshot? {
            try fetch(itemID: itemID).map {
                EmbeddingSnapshot(
                    vector: $0.vector,
                    textHash: $0.textHash
                )
            }
        }

        func saveIfCurrent(input: PendingInput, result: NLEmbeddingResult, token: UUID) async throws -> Bool {
            if let beforeSave {
                await beforeSave(input.itemID, input.text)
            }

            return try generationStore.withCurrentToken(itemID: input.itemID, token: token) {
                if let existing = try fetch(itemID: input.itemID) {
                    existing.kind = input.kind
                    existing.vector = result.vector
                    existing.textHash = result.textHash
                    existing.language = result.detectedLanguage
                    existing.vectorDimension = result.dimension
                    existing.updatedAt = .now
                } else {
                    context.insert(
                        ItemEmbedding(
                            itemID: input.itemID,
                            kind: input.kind,
                            vector: result.vector,
                            textHash: result.textHash,
                            language: result.detectedLanguage,
                            vectorDimension: result.dimension
                        )
                    )
                }

                try context.save()
                return true
            } ?? false
        }

        private func fetch(itemID: UUID) throws -> ItemEmbedding? {
            let descriptor = FetchDescriptor<ItemEmbedding>(
                predicate: #Predicate { $0.itemID == itemID }
            )
            return try context.fetch(descriptor).first
        }
    }

    private let client: any EmbeddingClient
    private let index: SqliteVecIndex
    private let generationStore = GenerationStore()
    private let persistence: EmbeddingPersistence
    private let debounce: Duration
    private var pending: [UUID: PendingWork] = [:]
    private let logger = Logger(
        subsystem: "com.kacperpietrzyk.nexus.agent",
        category: "EmbeddingDispatcher"
    )

    @MainActor
    public init(
        embeddingClient: any EmbeddingClient = NLEmbeddingClient(),
        index: SqliteVecIndex,
        context: ModelContext,
        debounce: Duration = .seconds(5)
    ) {
        self.client = embeddingClient
        self.index = index
        self.persistence = EmbeddingPersistence(
            context: context,
            generationStore: generationStore,
            beforeSave: nil
        )
        self.debounce = debounce
    }

    @MainActor
    init(
        embeddingClient: any EmbeddingClient,
        index: SqliteVecIndex,
        context: ModelContext,
        debounce: Duration,
        beforeSave: (@MainActor @Sendable (UUID, String) async -> Void)?
    ) {
        self.client = embeddingClient
        self.index = index
        self.persistence = EmbeddingPersistence(
            context: context,
            generationStore: generationStore,
            beforeSave: beforeSave
        )
        self.debounce = debounce
    }

    deinit {
        for work in pending.values {
            work.task.cancel()
        }
    }

    public func enqueue(itemID: UUID, kind: String, text: String) {
        pending[itemID]?.task.cancel()

        let input = PendingInput(itemID: itemID, kind: kind, text: text)
        let debounce = self.debounce
        let token = UUID()
        generationStore.setCurrent(itemID: itemID, token: token)
        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
                guard !Task.isCancelled else {
                    return
                }
                await self?.embed(input, token: token)
            } catch is CancellationError {
                return
            } catch {
                await self?.logSleepFailure(itemID: itemID, error: error)
            }
        }
        pending[itemID] = PendingWork(token: token, task: task)
    }

    public func cancel(itemID: UUID) {
        guard let work = pending.removeValue(forKey: itemID) else {
            return
        }
        work.task.cancel()
        generationStore.clearIfCurrent(itemID: itemID, token: work.token)
    }

    public func cancelAll() {
        for (itemID, work) in pending {
            work.task.cancel()
            generationStore.clearIfCurrent(itemID: itemID, token: work.token)
        }
        pending.removeAll()
    }

    public func pendingCount() -> Int {
        pending.count
    }

    public func waitUntilIdle(pollInterval: Duration = .milliseconds(10)) async throws {
        while !pending.isEmpty {
            try await Task.sleep(for: pollInterval)
        }
    }

    public func flush(itemID: UUID, kind: String, text: String) async {
        pending.removeValue(forKey: itemID)?.task.cancel()
        let token = UUID()
        generationStore.setCurrent(itemID: itemID, token: token)
        pending[itemID] = PendingWork(token: token, task: Task {})
        await embed(PendingInput(itemID: itemID, kind: kind, text: text), token: token)
    }

    private func embed(_ input: PendingInput, token: UUID) async {
        defer {
            clearPending(itemID: input.itemID, token: token)
        }

        do {
            guard isCurrent(itemID: input.itemID, token: token) else {
                return
            }

            let result = try await client.embed(input.text)
            guard isCurrent(itemID: input.itemID, token: token) else {
                return
            }

            let existing = try await persistence.snapshot(itemID: input.itemID)
            guard isCurrent(itemID: input.itemID, token: token) else {
                return
            }

            if let existing, existing.textHash == result.textHash {
                // Unchanged text: the DB already holds this embedding; only
                // rehydrate the (possibly rebuilt-empty) index. No DB write.
                try index.upsert(id: input.itemID, vector: existing.vector)
            } else {
                // Persist to the DB (source of truth) FIRST, then mirror into the
                // vector index — and only if the DB write actually happened. The
                // old order (index first) left two hazards: a crash between the
                // two stores left the index holding a vector the DB lacked, and
                // stale work updated the index even when its persist was rejected
                // by the token guard below. DB-first means a crash leaves the
                // index behind (safe — it gets re-embedded), never ahead.
                guard isCurrent(itemID: input.itemID, token: token) else {
                    return
                }
                let persisted = try await persistence.saveIfCurrent(
                    input: input, result: result, token: token)
                guard persisted else { return }
                try index.upsert(id: input.itemID, vector: result.vector)
            }
        } catch {
            logger.warning("embed failed for \(input.itemID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isCurrent(itemID: UUID, token: UUID) -> Bool {
        pending[itemID]?.token == token && generationStore.isCurrent(itemID: itemID, token: token)
    }

    private func clearPending(itemID: UUID, token: UUID) {
        guard isCurrent(itemID: itemID, token: token) else {
            return
        }
        pending.removeValue(forKey: itemID)
        generationStore.clearIfCurrent(itemID: itemID, token: token)
    }

    private func logSleepFailure(itemID: UUID, error: Error) {
        logger.warning("debounce sleep failed for \(itemID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}
