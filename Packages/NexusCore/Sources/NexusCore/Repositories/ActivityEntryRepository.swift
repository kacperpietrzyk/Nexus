import Foundation
import SwiftData

/// Append-only access to the `ActivityEntry` audit log, scoped by the subject
/// item id + kind (Tranche 2, Plan A foundation). `@MainActor` to match the
/// SwiftData isolation used across the repositories; one `context.save()` per
/// op (the `CommentRepository` save boundary).
///
/// Invariant I-B1: the log is append-only — this type deliberately exposes NO
/// update or delete API, `ActivityEntry` has no `deletedAt`, and it never
/// enters the `TombstonePurger` lifecycle (not `Linkable`).
///
/// Plan B note: `insert` (save-per-call) is the standalone/tooling write path.
/// The repository-hook writer (`ActivityRecorder`) inserts WITHOUT saving so
/// events commit atomically with their host mutation — it does not go through
/// this type. Plan B's reader contract is `entries(for:kind:limit:)` below;
/// reuse this type rather than adding a second log repository.
@MainActor
public struct ActivityEntryRepository {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    /// Inserts one audit event and saves. Returns the persisted entry.
    @discardableResult
    public func insert(
        itemID: UUID,
        itemKind: ItemKind,
        eventKind: ActivityEventKind,
        payloadJSON: String? = nil
    ) throws -> ActivityEntry {
        let entry = ActivityEntry(
            itemID: itemID,
            itemKind: itemKind,
            eventKind: eventKind,
            payloadJSON: payloadJSON
        )
        entry.createdAt = now()
        context.insert(entry)
        try context.save()
        return entry
    }

    /// Events for one item, newest first. `kind` disambiguates id collisions
    /// across entity tables (the polymorphic `Comment.comments(for:kind:)`
    /// contract). `limit` nil = all.
    public func entries(for itemID: UUID, kind: ItemKind, limit: Int? = nil) throws -> [ActivityEntry] {
        let raw = kind.rawValue
        var descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.itemID == itemID && $0.itemKindRaw == raw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try context.fetch(descriptor)
    }
}
