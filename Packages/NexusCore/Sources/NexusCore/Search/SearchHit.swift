import Foundation

/// A single result returned by `SearchIndex.search`. Designed to carry just enough for
/// a UI to render a row and deeplink: `(itemKind, itemID)` is the polymorphic D7 endpoint,
/// `snippet` is a short window of text around the first match (Phase 0d returns plain
/// `String`; Phase 1+ may switch to `AttributedString` for highlights), `score` is the
/// raw scorer output (TF-IDF) — higher is better, ordering only.
public struct SearchHit: Sendable, Equatable, Hashable {
    public let itemKind: ItemKind
    public let itemID: UUID
    public let snippet: String
    public let score: Double

    public init(itemKind: ItemKind, itemID: UUID, snippet: String, score: Double) {
        self.itemKind = itemKind
        self.itemID = itemID
        self.snippet = snippet
        self.score = score
    }
}
