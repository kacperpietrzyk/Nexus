import Foundation
import SwiftData

/// The universal content layer of the app (Notes module). The same type backs a
/// free-standing knowledge-base note, a Project's canonical page, a daily note,
/// and content attached to other entities.
///
/// Storage model: the canonical content is an ordered `[Block]` encoded into the
/// `contentData` Codable blob (block ids stay stable across decode — they anchor
/// the `NoteReconciler`'s mirror of cross-object refs into the `Link` graph).
/// `plainText` is a denormalized flatten of that content kept consistent by the
/// reconciler; it is the source for search/list/Watch so the hot path never
/// deserializes blocks.
///
/// Every stored property is defaulted/optional so the model is CloudKit-mirror
/// safe (private DB), mirroring `TaskItem`.
@Model
public final class Note: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.note
    public var title: String = ""
    /// Codable blob of `[Block]` (the canonical content). Decode via the Notes
    /// serializer (later step); never read on the hot list/search path — use
    /// `plainText` instead.
    public var contentData: Data = Data()
    /// Denormalized flatten of `contentData`, kept consistent by `NoteReconciler`.
    /// Source for search / list / Watch projection.
    public var plainText: String = ""
    public var role: NoteRole = NoteRole.free
    public var tags: [String] = []
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String = "",
        contentData: Data = Data(),
        plainText: String = "",
        role: NoteRole = .free,
        tags: [String] = []
    ) {
        self.id = id
        self.kind = .note
        self.title = title
        self.contentData = contentData
        self.plainText = plainText
        self.role = role
        self.tags = tags
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    /// `Searchable`: search indexes the denormalized `plainText` cache, never the
    /// raw block blob.
    public var searchableText: String { plainText }
}
