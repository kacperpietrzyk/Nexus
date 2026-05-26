import Foundation
import SwiftData

/// Refinement of `Linkable` for items that participate in the search index.
/// Conformers expose a single `searchableText` property which the index tokenizes.
/// Default implementation returns `title`, so any `Linkable` becomes searchable for free
/// when it adopts this protocol — but feature modules SHOULD override with a fuller text
/// (e.g. Note returns `title + "\n" + body`, Meeting returns `title + "\n" + transcript`).
public protocol Searchable: Linkable {
    var searchableText: String { get }
}

extension Searchable {
    public var searchableText: String { title }
}
