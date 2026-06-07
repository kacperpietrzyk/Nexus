import Foundation
import SwiftData

/// A single text comment anchored polymorphically to a task or project.
/// Single-user app: the author is always the user, so no author field.
/// Follows the raw id/kind convention (no SwiftData `@Relationship`), like the
/// rest of the Nexus model graph.
@Model
public final class Comment {
    public var id: UUID = UUID()
    /// Owning item's `id` (a `TaskItem.id` or `Project.id`).
    public var itemID: UUID = UUID()
    /// Owning item kind: `.task` or `.project`.
    public var itemKind: ItemKind = ItemKind.task
    public var body: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?
    /// External system identifier for idempotent imports
    /// (e.g. "todoist-comment:<id>").
    public var externalSourceID: String?

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        itemKind: ItemKind,
        body: String,
        externalSourceID: String? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.itemKind = itemKind
        self.body = body
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.externalSourceID = externalSourceID
    }
}
