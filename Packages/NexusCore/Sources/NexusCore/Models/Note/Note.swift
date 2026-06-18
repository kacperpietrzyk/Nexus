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
    /// Whether the user has pinned this note to the Today dashboard.
    /// Additive/defaulted — CloudKit-safe lightweight migration.
    public var isPinned: Bool = false
    /// When the note was most recently pinned. nil if never pinned.
    public var pinnedAt: Date?

    /// Custom property bag (Tranche 2, Obsidian O6). JSON-encoded ordered
    /// `[NoteProperty]` (array, NOT a dict — preserves user order so
    /// frontmatter emission stays deterministic). nil = no properties. Read
    /// and written through the `properties` accessor; views never touch the
    /// blob (Plan E routes edits through `NoteRepository`).
    public var propertiesJSON: String?

    /// Folder placement (Tranche 2, Obsidian O2). Slash-separated path
    /// ("area/subarea"), normalized via `NoteFolderPath.normalize` (no
    /// leading/trailing slash, no empty components); nil = root. There is NO
    /// folder entity — the tree is derived from live notes' paths.
    public var folderPath: String?

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

    /// Decoded view over `propertiesJSON` (the `TaskItem.reminders` idiom).
    /// Setting an empty array clears the stored blob; nil blob ⇔ []. Keys are
    /// de-duplicated last-wins, case-sensitively, on both read and write
    /// (defensive — the editor enforces uniqueness). SwiftData persists only
    /// `propertiesJSON`; this computed property is not part of the schema.
    public var properties: [NoteProperty] {
        get {
            guard let propertiesJSON,
                let data = propertiesJSON.data(using: .utf8),
                let decoded = try? JSONDecoder().decode([NoteProperty].self, from: data)
            else { return [] }
            return Self.deduplicatedLastWins(decoded)
        }
        set {
            let deduplicated = Self.deduplicatedLastWins(newValue)
            // `.sortedKeys` pins the blob byte-deterministic across runs and
            // devices (it syncs via CloudKit; the encode shape is golden-tested).
            // Dates ride the default `.deferredToDate` strategy (Double) —
            // never change either without a data migration for existing blobs.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard !deduplicated.isEmpty, let data = try? encoder.encode(deduplicated) else {
                propertiesJSON = nil
                return
            }
            propertiesJSON = String(data: data, encoding: .utf8)
        }
    }

    /// Keeps each key's LAST occurrence, in the surviving elements' original
    /// relative order (deterministic — frontmatter emission depends on it).
    private static func deduplicatedLastWins(_ properties: [NoteProperty]) -> [NoteProperty] {
        var seen = Set<String>()
        var keptReversed: [NoteProperty] = []
        for property in properties.reversed() where seen.insert(property.key).inserted {
            keptReversed.append(property)
        }
        return keptReversed.reversed()
    }
}
