import Foundation
import SwiftData

/// Hard-deletes soft-deleted Linkable rows older than `retention`.
@ModelActor
public actor TombstonePurger {
    public static let defaultRetention: TimeInterval = 60 * 60 * 24 * 30  // 30 days

    @discardableResult
    public func purge(
        olderThan retention: TimeInterval,
        now: Date = .now,
        types: [any Linkable.Type]
    ) throws -> Int {
        let cutoff = now.addingTimeInterval(-retention)
        var purged = 0
        for type in types {
            purged += try Self.purgeSingleType(type, cutoff: cutoff, in: modelContext)
        }
        try modelContext.save()
        return purged
    }

    private static func purgeSingleType(
        _ type: any Linkable.Type,
        cutoff: Date,
        in context: ModelContext
    ) throws -> Int {
        if type == DebugItem.self {
            return try purgeDebugItems(cutoff: cutoff, in: context)
        }
        if type == TaskItem.self {
            return try purgeTaskItems(cutoff: cutoff, in: context)
        }
        return 0
    }

    private static func purgeDebugItems(cutoff: Date, in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<DebugItem>(
            predicate: #Predicate { item in item.deletedAt != nil }
        )
        let tombstones = try context.fetch(descriptor)
        let stale = tombstones.filter { $0.deletedAt! < cutoff }
        for item in stale {
            context.delete(item)
        }
        return stale.count
    }

    private static func purgeTaskItems(cutoff: Date, in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { item in item.deletedAt != nil }
        )
        let tombstones = try context.fetch(descriptor)
        let stale = tombstones.filter { $0.deletedAt! < cutoff }
        for item in stale {
            context.delete(item)
        }
        return stale.count
    }
}
