import Foundation
import SwiftData

@Model
public final class Project: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.project
    public var name: String = ""
    /// Stores a legacy shape-token name (azure/gold/emerald/rose/violet/slate), retained to avoid
    /// schema migration. Since MP-2.1 slice 3c the value is a glyph key consumed via
    /// `nexusProjectGlyph(named:)` in TasksFeature; no color is rendered from it.
    public var color: String = "azure"
    public var parentProjectID: UUID?
    public var archivedAt: Date?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        color: String = "azure",
        parentProjectID: UUID? = nil
    ) {
        self.id = id
        self.kind = .project
        self.name = name
        self.color = color
        self.parentProjectID = parentProjectID
        self.archivedAt = nil
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    public var title: String {
        get { name }
        set { name = newValue }
    }

    public var searchableText: String { name }
}
