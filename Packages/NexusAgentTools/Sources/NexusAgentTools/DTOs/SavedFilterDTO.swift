import Foundation
import NexusCore

/// MCP-facing projection of a `SavedFilter`. The opaque `FilterDefinition`
/// payload is intentionally omitted from the DTO — callers create/update it as
/// free-form JSON and read results back as task lists via `saved_filters.apply`.
public struct SavedFilterDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let icon: String

    public init(from filter: SavedFilter) {
        self.id = filter.id.uuidString
        self.name = filter.name
        self.icon = filter.icon
    }
}
