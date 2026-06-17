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
}

extension InboxSource {
    public func count() async throws -> Int {
        try await items().count
    }

    public func items(limit: Int) async throws -> [InboxItem] {
        Array(try await items().prefix(limit))
    }
}
