import Foundation
import SwiftData

/// In-memory inverted-token search index. Pure Swift, no UIKit/AppKit/CoreSpotlight imports.
///
/// **State (actor-isolated):**
/// - `documents`: `[DocumentKey: StoredDocument]` — full text + per-doc term frequencies.
/// - `postings`: `[String: Set<DocumentKey>]` — which docs contain each token.
/// - `documentFrequencies`: `[String: Int]` — derived counter for IDF.
///
/// **Lifecycle:**
/// - Upsert (insert + restore): `upsert(_ doc: IndexedDocument)`. Idempotent — replaces any
///   prior version under the same `(kind, id)` key.
/// - Soft-delete: `remove(kind:id:)`. Idempotent — no-op if not indexed.
/// - Rebuild: see Task 7 (`rebuild(from:types:)`).
///
/// **Sendable:** `actor` isolates mutable state. `IndexedDocument` and `SearchHit` are `Sendable`
/// values, so all method signatures cross actor boundaries cleanly.
public actor SearchIndex: LinkableObserver {

    // MARK: - Internal state

    /// Composite key `(kind, id)` — D7 polymorphic identity.
    private struct DocumentKey: Hashable, Sendable {
        let kind: ItemKind
        let id: UUID
    }

    private struct StoredDocument: Sendable {
        let key: DocumentKey
        let text: String
        let termFrequencies: [String: Int]
        let updatedAt: Date
    }

    /// Lightweight intermediate row used during search: avoids building snippets for
    /// candidates that won't survive `prefix(limit)`.
    private struct ScoredEntry {
        let key: DocumentKey
        let score: Double
        let updatedAt: Date
    }

    private var documents: [DocumentKey: StoredDocument] = [:]
    private var postings: [String: Set<DocumentKey>] = [:]
    private var documentFrequencies: [String: Int] = [:]

    public init() {}

    // MARK: - Test helpers

    public var documentCount: Int { documents.count }

    // MARK: - Mutation

    public func upsert(_ document: IndexedDocument) {
        let key = DocumentKey(kind: document.kind, id: document.id)

        if documents[key] != nil {
            evictTokens(for: key)
        }

        let tokens = Tokenizer.tokenize(document.text)
        var tf: [String: Int] = [:]
        for token in tokens {
            tf[token, default: 0] += 1
        }

        for token in Set(tokens) {
            postings[token, default: []].insert(key)
            documentFrequencies[token, default: 0] += 1
        }

        documents[key] = StoredDocument(
            key: key,
            text: document.text,
            termFrequencies: tf,
            updatedAt: document.updatedAt
        )
    }

    public func remove(kind: ItemKind, id: UUID) {
        let key = DocumentKey(kind: kind, id: id)
        guard documents[key] != nil else { return }
        evictTokens(for: key)
        documents.removeValue(forKey: key)
    }

    public func clear() {
        documents.removeAll()
        postings.removeAll()
        documentFrequencies.removeAll()
    }

    private func evictTokens(for key: DocumentKey) {
        guard let stored = documents[key] else { return }
        for (token, _) in stored.termFrequencies {
            if var set = postings[token] {
                set.remove(key)
                if set.isEmpty {
                    postings.removeValue(forKey: token)
                } else {
                    postings[token] = set
                }
            }
            if let df = documentFrequencies[token] {
                if df <= 1 {
                    documentFrequencies.removeValue(forKey: token)
                } else {
                    documentFrequencies[token] = df - 1
                }
            }
        }
    }

    // MARK: - Query

    public func search(_ query: String, kinds: Set<ItemKind>?, limit: Int) -> [SearchHit] {
        guard limit > 0 else { return [] }
        let queryTokens = Tokenizer.tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        var candidates: Set<DocumentKey> = []
        for token in queryTokens {
            if let docs = postings[token] {
                candidates.formUnion(docs)
            }
        }

        if let kinds {
            candidates = candidates.filter { kinds.contains($0.kind) }
        }

        let total = documents.count

        // Phase 1: cheap scoring without snippet building.
        var scored: [ScoredEntry] = []
        scored.reserveCapacity(candidates.count)
        for key in candidates {
            guard let stored = documents[key] else { continue }
            let score = Scorer.score(
                queryTokens: queryTokens,
                documentTermFrequencies: stored.termFrequencies,
                documentFrequencies: documentFrequencies,
                totalDocuments: total
            )
            guard score > 0 else { continue }
            scored.append(ScoredEntry(key: key, score: score, updatedAt: stored.updatedAt))
        }

        // Phase 2: deterministic sort. Score desc, then recency desc (newer first when tied —
        // "find the thing I worked on recently"), uuidString asc as final tiebreaker.
        scored.sort { (a, b) in
            if a.score != b.score { return a.score > b.score }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return a.key.id.uuidString < b.key.id.uuidString
        }

        // Phase 3: snippet only for the survivors that fit `limit`.
        return scored.prefix(limit).compactMap { entry in
            guard let stored = documents[entry.key] else { return nil }
            let snippet = Snippetizer.snippet(query: query, text: stored.text, radius: 40)
            return SearchHit(
                itemKind: entry.key.kind,
                itemID: entry.key.id,
                snippet: snippet,
                score: entry.score
            )
        }
    }

    // MARK: - LinkableObserver

    public func didUpsert(_ document: IndexedDocument) async {
        upsert(document)
    }

    public func didSoftDelete(kind: ItemKind, id: UUID) async {
        remove(kind: kind, id: id)
    }

    // MARK: - Rebuild from SwiftData

    private func replaceAll(with snapshots: [IndexedDocument]) {
        clear()
        for doc in snapshots {
            upsert(doc)
        }
    }

    /// Wipes the index and repopulates it from every live (non-tombstoned) `Searchable` row
    /// found in `context` for the listed `types`. Variadic generics let the composition root
    /// list every concrete `Searchable` model registered in `NexusSchemaV1`.
    ///
    /// Called from `@MainActor` (where the `ModelContext` is safe to read). Snapshots are
    /// extracted into `Sendable` `IndexedDocument` values before being awaited into the actor.
    /// Method is `@MainActor` so the SwiftData fetch happens on the model's owning actor;
    /// the index actor is then awaited explicitly via `replaceAll`.
    @MainActor
    public func rebuild<each S: Searchable>(
        from context: ModelContext,
        types: repeat (each S).Type
    ) async throws {
        let snapshots = try Self.collectSnapshots(from: context, types: repeat (each S).self)
        await replaceAll(with: snapshots)
    }

    /// Synchronously fetches live rows of every requested type from `context` and snapshots
    /// them into Sendable `IndexedDocument` values. `@MainActor`-isolated so SwiftData reads
    /// are safe.
    @MainActor
    private static func collectSnapshots<each S: Searchable>(
        from context: ModelContext,
        types: repeat (each S).Type
    ) throws -> [IndexedDocument] {
        var docs: [IndexedDocument] = []
        repeat docs.append(contentsOf: try fetchSnapshots((each S).self, from: context))
        return docs
    }

    @MainActor
    private static func fetchSnapshots<S: Searchable>(
        _ type: S.Type,
        from context: ModelContext
    ) throws -> [IndexedDocument] {
        // Fetch every row and filter `deletedAt == nil` in Swift rather than via a
        // `#Predicate<S>`. A predicate built over the generic protocol type `S` synthesizes a
        // keypath through the `Searchable`/`Linkable` witness that SwiftData cannot match
        // against the concrete model's registered schema keypath in optimized (Release) builds —
        // it traps in `DataUtilities` with "Couldn't find \Model.<computed …>". Fetching all and
        // filtering in memory avoids keypath translation entirely; tombstone volume is bounded by
        // `TombstonePurger`, so the cost is negligible at single-user scale.
        let descriptor = FetchDescriptor<S>()
        return try context.fetch(descriptor)
            .filter { $0.deletedAt == nil }
            .map { IndexedDocument($0) }
    }
}
