import CoreSpotlight
import Foundation
import NexusCore

/// Composition-root container for the in-app search engine + Spotlight bridge.
/// Apps build a single instance at launch and inject it (plus its `observers` list) into
/// the `LinkableRepository`s and SwiftUI environment.
public final class SearchSubsystem: Sendable {
    public let searchIndex: SearchIndex
    public let spotlightIndexer: SpotlightIndexer
    public let observers: [any LinkableObserver]

    public init(searchIndex: SearchIndex, spotlightIndexer: SpotlightIndexer) {
        self.searchIndex = searchIndex
        self.spotlightIndexer = spotlightIndexer
        self.observers = [searchIndex, spotlightIndexer]
    }

    public static func makeLive() -> SearchSubsystem {
        SearchSubsystem(
            searchIndex: SearchIndex(),
            spotlightIndexer: SpotlightIndexer()
        )
    }

    public static func makeForTesting(spotlightIndex: any SpotlightIndex = NoopSpotlightIndex()) -> SearchSubsystem {
        SearchSubsystem(
            searchIndex: SearchIndex(),
            spotlightIndexer: SpotlightIndexer(index: spotlightIndex)
        )
    }
}

/// Drop-in `SpotlightIndex` that swallows everything. Default for tests + previews.
public struct NoopSpotlightIndex: SpotlightIndex {
    public init() {}
    public func indexSearchableItems(_ items: [CSSearchableItem]) async throws {}
    public func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {}
}
