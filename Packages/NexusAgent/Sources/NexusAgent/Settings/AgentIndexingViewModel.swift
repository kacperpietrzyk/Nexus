import Combine
import Foundation
import NexusCore
import SwiftData

@MainActor
public final class AgentIndexingViewModel: ObservableObject {
    public struct Coverage: Equatable, Sendable {
        public let indexed: Int
        public let total: Int
        public let ratio: Double

        public init(indexed: Int = 0, total: Int = 0) {
            self.indexed = indexed
            self.total = total
            self.ratio = total == 0 ? 1.0 : Double(indexed) / Double(total)
        }
    }

    @Published public private(set) var coverage = Coverage()
    @Published public private(set) var isRebuilding = false
    @Published public private(set) var lastProgress: BackfillProgress?
    @Published public private(set) var lastRebuildAt: Date?

    private let context: ModelContext
    private let backfill: BackfillEmbeddingsJob

    public init(context: ModelContext, backfill: BackfillEmbeddingsJob) {
        self.context = context
        self.backfill = backfill
        refresh()
    }

    public func refresh() {
        do {
            let tasks = try context.fetch(FetchDescriptor<TaskItem>())
                .filter { $0.deletedAt == nil }
            let memories = try context.fetch(FetchDescriptor<AgentMemoryEntry>())
                .filter { $0.deletedAt == nil }
            let liveIDs = Set(tasks.map(\.id)).union(memories.map(\.id))
            let indexedIDs = Set(
                try context.fetch(FetchDescriptor<ItemEmbedding>())
                    .map(\.itemID)
                    .filter { liveIDs.contains($0) }
            )
            coverage = Coverage(indexed: indexedIDs.count, total: liveIDs.count)
        } catch {
            coverage = Coverage()
        }
    }

    public func rebuild() async {
        guard !isRebuilding else {
            return
        }

        isRebuilding = true
        defer {
            isRebuilding = false
            refresh()
        }

        do {
            if let progress = try await backfill.runIfIdle() {
                lastProgress = progress
                lastRebuildAt = .now
            }
        } catch {
            lastProgress = BackfillProgress(processed: 0, skipped: 0, total: 0)
        }
    }
}
