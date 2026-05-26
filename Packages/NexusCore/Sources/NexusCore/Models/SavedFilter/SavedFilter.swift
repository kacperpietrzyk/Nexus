import Foundation
import SwiftData

@Model
public final class SavedFilter: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.savedFilter
    public var name: String = ""
    public var icon: String = "line.3.horizontal.decrease.circle"
    public var orderIndex: Double = 0.0
    /// Codable-encoded `FilterDefinition`. SwiftData stores Data; decoded in repository.
    public var definitionJSON: Data = Data()
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "line.3.horizontal.decrease.circle",
        definition: FilterDefinition,
        orderIndex: Double = 0.0
    ) throws {
        self.id = id
        self.kind = .savedFilter
        self.name = name
        self.icon = icon
        self.orderIndex = orderIndex
        self.definitionJSON = try JSONEncoder().encode(definition)
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    public var title: String {
        get { name }
        set { name = newValue }
    }

    /// Lossy convenience for legacy UI paths: corrupt stored data falls back to `.unsorted`.
    /// Use `decodedDefinition()` in repositories and code paths that can report errors.
    public var definition: FilterDefinition {
        (try? decodedDefinition()) ?? .unsorted
    }

    public func decodedDefinition() throws -> FilterDefinition {
        try JSONDecoder().decode(FilterDefinition.self, from: definitionJSON)
    }

    public func setDefinition(_ definition: FilterDefinition) throws {
        self.definitionJSON = try JSONEncoder().encode(definition)
        self.updatedAt = Date.now
    }

    public var searchableText: String { name }
}
