import Foundation
import SwiftData

/// Read/upsert access to `FeedItemState`, keyed by the stable feed `key`.
/// `@MainActor` to match the SwiftData isolation used across repositories;
/// one `context.save()` per `upsert`.
@MainActor
public struct FeedItemStateRepository {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    /// All states keyed by `key`. Collapses duplicate rows (a CloudKit sync race
    /// can create them since `key` is not unique): the newest `updatedAt` wins
    /// and the stale rows are deleted (saved).
    public func all() throws -> [String: FeedItemState] {
        let rows = try context.fetch(FetchDescriptor<FeedItemState>())
        var byKey: [String: FeedItemState] = [:]
        var stale: [FeedItemState] = []
        for row in rows {
            if let existing = byKey[row.key] {
                if row.updatedAt > existing.updatedAt {
                    stale.append(existing)
                    byKey[row.key] = row
                } else {
                    stale.append(row)
                }
            } else {
                byKey[row.key] = row
            }
        }
        if !stale.isEmpty {
            for row in stale { context.delete(row) }
            try context.save()
        }
        return byKey
    }

    /// Fetch-or-insert by `key`, apply `mutate`, stamp `updatedAt`, save.
    @discardableResult
    public func upsert(key: String, mutate: (FeedItemState) -> Void) throws -> FeedItemState {
        let existing = try all()[key]
        let state = existing ?? FeedItemState(key: key)
        if existing == nil { context.insert(state) }
        mutate(state)
        state.updatedAt = now()
        try context.save()
        return state
    }
}
