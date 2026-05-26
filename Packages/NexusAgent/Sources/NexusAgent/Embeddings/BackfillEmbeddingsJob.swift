import Foundation
import NexusCore
import SwiftData
import os

public struct BackfillProgress: Equatable, Sendable {
    public let processed: Int
    public let skipped: Int
    public let total: Int

    public init(processed: Int, skipped: Int, total: Int) {
        self.processed = processed
        self.skipped = skipped
        self.total = total
    }
}

@MainActor
public final class BackfillEmbeddingsJob {
    private let context: ModelContext
    private let dispatcher: EmbeddingDispatcher
    private let index: SqliteVecIndex?
    private var isRunning = false
    private let logger = Logger(
        subsystem: "com.kacperpietrzyk.nexus.agent",
        category: "BackfillEmbeddingsJob"
    )

    public init(
        context: ModelContext,
        dispatcher: EmbeddingDispatcher,
        index: SqliteVecIndex? = nil
    ) {
        self.context = context
        self.dispatcher = dispatcher
        self.index = index
    }

    public func run() async throws -> BackfillProgress {
        let tasks = try liveTasks()
        let memories = try liveMemories()
        let embeddedIDs = try existingEmbeddingIDs()
        let liveIDs = Set(tasks.map(\.id)).union(memories.map(\.id))
        try cleanupStaleEmbeddings(liveIDs: liveIDs)
        var processed = 0
        var skipped = 0

        for task in tasks {
            if embeddedIDs.contains(task.id) {
                skipped += 1
            } else {
                processed += 1
            }
            await dispatcher.enqueue(
                itemID: task.id,
                kind: ItemKind.task.rawValue,
                text: task.searchableText
            )
        }

        for memory in memories {
            if embeddedIDs.contains(memory.id) {
                skipped += 1
            } else {
                processed += 1
            }
            await dispatcher.enqueue(
                itemID: memory.id,
                kind: ItemKind.agentMemory.rawValue,
                text: memory.searchableText
            )
        }

        try await dispatcher.waitUntilIdle()

        let progress = BackfillProgress(
            processed: processed,
            skipped: skipped,
            total: tasks.count + memories.count
        )
        logger.info(
            "backfill processed=\(progress.processed) skipped=\(progress.skipped) total=\(progress.total)"
        )
        return progress
    }

    public func runIfIdle() async throws -> BackfillProgress? {
        guard !isRunning else {
            return nil
        }

        isRunning = true
        defer { isRunning = false }
        return try await run()
    }

    private func liveTasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.deletedAt == nil }
    }

    private func liveMemories() throws -> [AgentMemoryEntry] {
        try context.fetch(FetchDescriptor<AgentMemoryEntry>())
            .filter { $0.deletedAt == nil }
    }

    private func existingEmbeddingIDs() throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<ItemEmbedding>()).map(\.itemID))
    }

    private func cleanupStaleEmbeddings(liveIDs: Set<UUID>) throws {
        let embeddings = try context.fetch(FetchDescriptor<ItemEmbedding>())
        let staleEmbeddings = embeddings.filter { !liveIDs.contains($0.itemID) }
        guard !staleEmbeddings.isEmpty else {
            return
        }

        for embedding in staleEmbeddings {
            try index?.delete(id: embedding.itemID)
            context.delete(embedding)
        }
        try context.save()
    }
}
