import Foundation
import SwiftData

/// One append-only audit-log event for a task/project/note (Tranche 2,
/// Linear L3 / Todoist T6). Never updated, never soft-deleted (no `deletedAt`
/// — invariant I-B1); written ONLY from repository mutation points, never from
/// views. Synced (CloudKit private DB).
///
/// Deliberately NOT `Linkable` (append-only rows have no mutable
/// `title`/`updatedAt`/`deletedAt` and must never enter the
/// soft-delete/`TombstonePurger` lifecycle), NOT `Searchable`, and NOT a new
/// `ItemKind` — it is metadata ABOUT graph items, not a graph item. Modeled on
/// `Comment` (plain `@Model` anchored polymorphically by raw item id/kind, all
/// fields defaulted for the CloudKit mirror).
@Model
public final class ActivityEntry {
    public var id: UUID = UUID()
    /// Subject item's kind, raw `ItemKind` value ("task"/"project"/"note").
    /// Stored raw (locked decision); `Comment.itemKind` stores the enum
    /// directly — both shapes are CloudKit-proven.
    public var itemKindRaw: String = ItemKind.task.rawValue
    /// Subject item's `id` (e.g. `TaskItem.id`).
    public var itemID: UUID = UUID()
    /// `ActivityEventKind` raw.
    public var eventKindRaw: String = ""
    /// Optional JSON payload, e.g. {"old":"todo","new":"inProgress"} — small,
    /// human-readable old/new values keyed "old"/"new" (raw enum values, UUID
    /// strings, or ISO8601 dates).
    public var payloadJSON: String?
    public var createdAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        itemKind: ItemKind,
        eventKind: ActivityEventKind,
        payloadJSON: String? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.itemKindRaw = itemKind.rawValue
        self.eventKindRaw = eventKind.rawValue
        self.payloadJSON = payloadJSON
        self.createdAt = Date.now
    }

    /// Get-only view over `itemKindRaw` (the `TaskItem.workflowState` idiom).
    /// nil for an unknown stored raw — forward compat with kinds synced from a
    /// newer build.
    public var itemKind: ItemKind? {
        ItemKind(rawValue: itemKindRaw)
    }

    /// Get-only view over `eventKindRaw`. nil for an unknown stored raw — a
    /// renderer must show a generic "updated" row, never crash.
    public var eventKind: ActivityEventKind? {
        ActivityEventKind(rawValue: eventKindRaw)
    }
}
