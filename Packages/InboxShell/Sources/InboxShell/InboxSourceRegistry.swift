import CoreData
import Foundation
import SwiftData

public enum InboxSourceRegistryError: Error, Equatable {
    case missingSource(String)
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
