import Foundation

public protocol InboxSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }

    func items() async throws -> [InboxItem]
    func archive(_ item: InboxItem) async throws
    func snooze(_ item: InboxItem, until date: Date) async throws

    /// Total number of items this source would surface, WITHOUT materializing
    /// them. Default materializes `items()`; high-volume sources (the no-date
    /// tasks source) override with a cheap `fetchCount` so the Inbox unread/tab
    /// counts stay accurate while the item list is only windowed.
    func count() async throws -> Int

    /// The first `limit` items in this source's natural order. Default returns
    /// the full `items()` (correct for small sources); the dominant source
    /// overrides to fetch only a window so a cold Inbox entry doesn't
    /// materialize thousands of rows. Returning the first `limit` (rather than
    /// an offset page) keeps the cross-source merge order-correct and re-entry
    /// simple.
    func items(limit: Int) async throws -> [InboxItem]

    /// Permanently deletes an item. The default delegates to `archive` so
    /// existing conformers need no change; sources that support real deletion
    /// (e.g. a TasksSource backed by a repo) should override to call their
    /// hard-delete path. The default is intentionally non-throwing on the
    /// delete semantics because even the archive fallback removes the item
    /// from the live list.
    func delete(_ item: InboxItem) async throws

    /// Restores a previously archived/deleted item. Default is a no-op because
    /// the protocol has no restore path today; sources that support undo
    /// (e.g. TasksSource with a soft-delete repo) should override. The undo
    /// toast is wired to this — the toast will still show, but pressing Undo
    /// silently no-ops for sources that don't implement restore.
    func restore(_ item: InboxItem) async throws
}

extension InboxSource {
    public func count() async throws -> Int {
        try await items().count
    }

    public func items(limit: Int) async throws -> [InboxItem] {
        Array(try await items().prefix(limit))
    }

    public func delete(_ item: InboxItem) async throws {
        try await archive(item)
    }

    public func restore(_: InboxItem) async throws {
        // no-op default — sources must override for real undo support
    }
}
