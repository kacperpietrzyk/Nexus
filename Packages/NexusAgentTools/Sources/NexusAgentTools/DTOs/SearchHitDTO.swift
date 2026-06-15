import Foundation
import NexusCore

/// Wire format for a unified-search result row.
///
/// Maps a `SearchHit` (the polymorphic `(itemKind, itemID)` D7 endpoint plus a text
/// `snippet` and the raw scorer `score`) into a flat JSON-friendly shape. `SearchHit`
/// carries no title — the snippet is the only text it exposes, so MCP clients deeplink
/// via `(kind, id)` and render the snippet as the row label.
public struct SearchHitDTO: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let snippet: String
    public let score: Double

    public init(from hit: SearchHit) {
        self.id = hit.itemID.uuidString
        self.kind = hit.itemKind.rawValue
        self.snippet = hit.snippet
        self.score = hit.score
    }
}
