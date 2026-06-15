import Foundation
import SwiftData

/// Repository-level audit-log hook (Tranche 2 Plan B, spec §4.1). Defined in
/// NexusCore beside `NotificationScheduling` — the same injection seam.
///
/// Invariant I-B1: implementations ONLY insert `ActivityEntry` rows into the
/// host repository's `ModelContext` and NEVER call `context.save()` — the
/// entry rides the host mutation's save, so event + mutation commit atomically
/// and a failed save loses both together. Written ONLY from repository
/// mutation points; views and agent tools never record directly.
///
/// `@MainActor` because conformers operate on a MainActor-bound `ModelContext`
/// (the `NotificationScheduling` precedent).
@MainActor
public protocol ActivityRecording: Sendable {
    func record(_ eventKind: ActivityEventKind, itemID: UUID, itemKind: ItemKind, payloadJSON: String?)
}

extension ActivityRecording {
    /// Payload-less convenience (created/completed/reopened/deleted).
    public func record(_ eventKind: ActivityEventKind, itemID: UUID, itemKind: ItemKind) {
        record(eventKind, itemID: itemID, itemKind: itemKind, payloadJSON: nil)
    }

    /// Old/new convenience for diff-carrying events.
    public func recordChange(
        _ eventKind: ActivityEventKind,
        itemID: UUID,
        itemKind: ItemKind,
        old: String?,
        new: String?
    ) {
        record(
            eventKind,
            itemID: itemID,
            itemKind: itemKind,
            payloadJSON: ActivityChangePayload(old: old, new: new).encodedJSON
        )
    }
}

/// Default no-op (the `NoopNotificationScheduler` pattern) so existing
/// repository call sites and tests stay unaffected unless they opt in.
public struct NoopActivityRecorder: ActivityRecording {
    public init() {}
    public func record(_: ActivityEventKind, itemID _: UUID, itemKind _: ItemKind, payloadJSON _: String?) {}
}

/// Production recorder: context-bound, insert-only (never saves — I-B1).
@MainActor
public final class ActivityRecorder: ActivityRecording {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    public func record(_ eventKind: ActivityEventKind, itemID: UUID, itemKind: ItemKind, payloadJSON: String?) {
        let entry = ActivityEntry(
            itemID: itemID,
            itemKind: itemKind,
            eventKind: eventKind,
            payloadJSON: payloadJSON
        )
        // `ActivityEntry.init` stamps `Date.now`; re-stamp with the injected
        // clock (the `ActivityEntryRepository.insert` precedent).
        entry.createdAt = now()
        context.insert(entry)
        // NO context.save() — ever. See protocol doc (I-B1).
    }
}
