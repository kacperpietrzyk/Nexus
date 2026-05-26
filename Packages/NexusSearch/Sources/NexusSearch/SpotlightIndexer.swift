import CoreSpotlight
import Foundation
import NexusCore
import os.log

/// `CSSearchableItem` is an Objective-C class (`NSObject` subclass) that the CoreSpotlight
/// SDK does not annotate as `Sendable`. After construction by `SpotlightAttributeSetMapping`
/// we treat it as a value-like immutable payload — never mutated, only handed to the index —
/// so we declare unchecked `Sendable` here. This lets actor-isolated `SpotlightIndex` doubles
/// store and surface them without Swift 6 strict-concurrency errors.
extension CSSearchableItem: @retroactive @unchecked Sendable {}

/// Minimal protocol for the parts of `CSSearchableIndex` we use. Lets tests inject a
/// recording double without touching the live system index.
public protocol SpotlightIndex: Sendable {
    func indexSearchableItems(_ items: [CSSearchableItem]) async throws
    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws
}

/// `CSSearchableIndex` itself is `Sendable` per Apple's framework annotations on iOS 16+/macOS 13+.
/// We extend it to satisfy our protocol.
extension CSSearchableIndex: SpotlightIndex {}

/// `LinkableObserver` that bridges Linkable upsert/soft-delete events into CoreSpotlight.
/// Mac + iOS only (this entire package is). Errors from the backing index are logged and
/// swallowed — search engine correctness must NOT depend on Spotlight succeeding (Spotlight
/// is best-effort enrichment). The in-memory `SearchIndex` is the source of truth for
/// in-app queries; `SpotlightIndexer` only feeds the system search bar.
public actor SpotlightIndexer: LinkableObserver {
    private let index: any SpotlightIndex
    private let log = Logger(subsystem: SpotlightDomain.root, category: "spotlight-indexer")

    public init(index: any SpotlightIndex = CSSearchableIndex.default()) {
        self.index = index
    }

    public func didUpsert(_ document: IndexedDocument) async {
        let item = SpotlightAttributeSetMapping.makeSearchableItem(for: document)
        do {
            try await index.indexSearchableItems([item])
        } catch {
            let identifier = SpotlightDomain.uniqueIdentifier(kind: document.kind, id: document.id)
            log.error(
                "spotlight upsert failed for \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func didSoftDelete(kind: ItemKind, id: UUID) async {
        let identifier = SpotlightDomain.uniqueIdentifier(kind: kind, id: id)
        do {
            try await index.deleteSearchableItems(withIdentifiers: [identifier])
        } catch {
            log.error(
                "spotlight delete failed for \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
