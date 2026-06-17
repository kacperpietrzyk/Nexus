import CoreData
import Foundation
import SwiftData

public enum InboxSourceRegistryError: Error, Equatable {
    case missingSource(String)
}

/// A windowed snapshot of the inbox for the sectioned (macOS) view: the merged
/// + globally-sorted item window PLUS each registered source's TRUE total count
/// (uncapped), so the section/tab/badge counts stay accurate while the rendered
/// list only materializes a page. Unlike the flat `items(limit:)`, this does NOT
/// prefix-cap the merge — a small source whose items have older `createdAt` than
/// the dominant no-date source must not be starved out of its section.
public struct InboxWindow: Sendable {
    public let items: [InboxItem]
    public let totalsBySourceID: [String: Int]

    public init(items: [InboxItem], totalsBySourceID: [String: Int]) {
        self.items = items
        self.totalsBySourceID = totalsBySourceID
    }

    /// Sum of every source's true count — the accurate grand total used for the
    /// unread badge (`max(0, totalItemCount - readCount)`) and the "All" tab.
    public var totalItemCount: Int {
        totalsBySourceID.values.reduce(0, +)
    }
}

public actor InboxSourceRegistry {
    public static let shared = InboxSourceRegistry()

    private var sources: [String: any InboxSource] = [:]
    // Cache of the fully computed + sorted item list. `InboxView.reload` calls
    // `allItems()` on every Inbox appear; materializing all source items and
    // walking the Link graph each time hung entry (~seconds, proven by a macOS
    // `sample`). The cache makes a plain re-entry instant; a real store write
    // invalidates it via `invalidateCache()` so freshness is preserved.
    private var cachedItems: [InboxItem]?
    // Store-change observers kept alive for the registry's whole lifetime.
    // InboxView's own `reloadOnStoreChange` only fires while the Inbox tab is
    // mounted; a write made on another tab (or a CloudKit/helper import) would
    // otherwise leave the shared cache stale until the next *mounted* reload,
    // re-introducing the "switch tabs to see changes" staleness on re-entry.
    // Self-invalidation here is cheap (`cachedItems = nil`); the expensive
    // recompute still happens only on a mounted `allItems()` call.
    // `nonisolated(unsafe)` so the nonisolated `deinit` can release the tokens:
    // safe because the array is mutated only once, from the actor-isolated
    // `startObservingStoreChangesIfNeeded()`, and read only in `deinit`, which
    // runs after every reference is gone — there is no concurrent access.
    private nonisolated(unsafe) var storeObservers: [NSObjectProtocol] = []
    private var didStartObserving = false

    public init() {}

    deinit {
        for observer in storeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Subscribe to local saves (`ModelContext.didSave`) and remote/cross-process
    /// imports (`.NSPersistentStoreRemoteChange`) so the cache self-invalidates
    /// even when no `InboxView` is mounted — a write on another tab (or a
    /// CloudKit/helper import) would otherwise leave the shared cache stale
    /// until the next *mounted* reload. Registered lazily from `allItems()`
    /// (an isolated context, so self-capture is legal): the cache only exists
    /// after the first `allItems()`, so observation starting then cannot miss a
    /// stale-making event. The no-`await` window below makes it run once.
    private func startObservingStoreChangesIfNeeded() {
        guard !didStartObserving else { return }
        didStartObserving = true
        let names: [Notification.Name] = [ModelContext.didSave, .NSPersistentStoreRemoteChange]
        storeObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                Task { await self.invalidateCache() }
            }
        }
    }

    public func register(_ source: any InboxSource) {
        sources[source.id] = source
        cachedItems = nil
    }

    public func unregister(id: String) {
        sources[id] = nil
        cachedItems = nil
    }

    public func sourceIDs() -> [String] {
        sources.keys.sorted()
    }

    public func allItems() async throws -> [InboxItem] {
        startObservingStoreChangesIfNeeded()
        if let cachedItems { return cachedItems }
        var result: [InboxItem] = []
        for source in sources.values {
            result.append(contentsOf: try await source.items())
        }
        let sorted = result.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        cachedItems = sorted
        return sorted
    }

    /// Drops the cached item list so the next `allItems()` re-queries every
    /// source. Call after a real change (store write, archive/snooze) so the
    /// Inbox refreshes; a plain re-appear reuses the cache for instant entry.
    public func invalidateCache() {
        cachedItems = nil
    }

    /// Windowed merge: every source is asked for at most `limit` items (small
    /// sources return their full set; the dominant no-date source returns only
    /// its first `limit` in `createdAt`-desc order), then merged + globally
    /// sorted and capped to `limit`. The result is the TRUE global first
    /// `limit` (each source can contribute at most `limit` to the head, so
    /// asking each for `limit` is sufficient). Uncached — materializing only
    /// `limit` rows is cheap, so a cold Inbox entry no longer hangs on ~1383.
    public func items(limit: Int) async throws -> [InboxItem] {
        startObservingStoreChangesIfNeeded()
        var result: [InboxItem] = []
        for source in sources.values {
            result.append(contentsOf: try await source.items(limit: limit))
        }
        let sorted = result.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }

    /// Windowed snapshot for the sectioned view: each source's first `limit`
    /// items (small sources return their full set) merged + globally sorted,
    /// with NO prefix cap, plus every source's true `count()`. Dropping the cap
    /// (vs `items(limit:)`) is what keeps a small, older-`createdAt` source from
    /// being starved out of its section by the dominant no-date source — the
    /// merge holds at most `limit` per source, which is bounded and cheap.
    public func window(limit: Int) async throws -> InboxWindow {
        startObservingStoreChangesIfNeeded()
        var merged: [InboxItem] = []
        var totals: [String: Int] = [:]
        for source in sources.values {
            merged.append(contentsOf: try await source.items(limit: limit))
            totals[source.id] = try await source.count()
        }
        let sorted = merged.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return InboxWindow(items: sorted, totalsBySourceID: totals)
    }

    /// Sum of every source's true `count()` — the accurate Inbox total WITHOUT
    /// materializing the items, so the unread/tab badges stay correct while the
    /// list is only windowed.
    public func totalCount() async throws -> Int {
        var total = 0
        for source in sources.values {
            total += try await source.count()
        }
        return total
    }

    public func archive(_ item: InboxItem) async throws {
        guard let source = sources[item.sourceID] else {
            throw InboxSourceRegistryError.missingSource(item.sourceID)
        }
        try await source.archive(item)
    }

    public func snooze(_ item: InboxItem, until date: Date) async throws {
        guard let source = sources[item.sourceID] else {
            throw InboxSourceRegistryError.missingSource(item.sourceID)
        }
        try await source.snooze(item, until: date)
    }
}
