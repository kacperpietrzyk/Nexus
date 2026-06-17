import Foundation
import InboxShell
import Testing

@Suite("InboxSourceRegistry")
struct InboxSourceRegistryTests {

    private func item(_ source: String, _ offset: TimeInterval) -> InboxItem {
        InboxItem(
            id: UUID(),
            sourceID: source,
            title: "\(source)-\(Int(offset))",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(offset)
        )
    }

    @Test("items(limit:) returns the global-first-N, merged + sorted, capped to limit")
    func windowedItemsReturnsGlobalFirstN() async throws {
        let registry = InboxSourceRegistry()
        await registry.register(RecordingInboxSource(id: "A", items: [item("A", 30), item("A", 20), item("A", 10)]))
        await registry.register(RecordingInboxSource(id: "B", items: [item("B", 25), item("B", 5)]))
        // Global createdAt-desc order across both sources: 30, 25, 20, 10, 5.
        let window = try await registry.items(limit: 3)
        let offsets = window.map { Int($0.createdAt.timeIntervalSince1970 - 1_000_000) }
        #expect(offsets == [30, 25, 20])
    }

    @Test("window(limit:) windows the dominant source but keeps small sources whole + reports true totals")
    func windowKeepsSmallSourcesWhole() async throws {
        let registry = InboxSourceRegistry()
        // Dominant source: 5 items, all NEWER than the small source — a global
        // prefix(2) merge would fill the window entirely from here and starve
        // the small source out of its section.
        await registry.register(
            RecordingInboxSource(
                id: "big",
                items: [item("big", 100), item("big", 90), item("big", 80), item("big", 70), item("big", 60)]
            )
        )
        // Small source: 2 OLDER items.
        await registry.register(RecordingInboxSource(id: "small", items: [item("small", 20), item("small", 10)]))

        let window = try await registry.window(limit: 2)
        let bySource = Dictionary(grouping: window.items, by: \.sourceID).mapValues(\.count)
        // Big source windowed to `limit`; small source NOT starved (full set kept).
        #expect(bySource["big"] == 2)
        #expect(bySource["small"] == 2)
        // True totals are uncapped, regardless of the window size.
        #expect(window.totalsBySourceID == ["big": 5, "small": 2])
        #expect(window.totalItemCount == 7)
        // Merge is globally sorted newest-first across both sources.
        #expect(window.items.map(\.sourceID) == ["big", "big", "small", "small"])
    }

    @Test("totalCount sums sources' count() without materializing items")
    func totalCountSumsWithoutMaterializing() async throws {
        let registry = InboxSourceRegistry()
        let big = CountOnlyInboxSource(id: "big", count: 1000)
        let small = CountOnlyInboxSource(id: "small", count: 7)
        await registry.register(big)
        await registry.register(small)
        let total = try await registry.totalCount()
        #expect(total == 1007)
        #expect(await big.itemsWasMaterialized == false)
        #expect(await small.itemsWasMaterialized == false)
    }

    @Test("allItems aggregates registered sources and sorts newest first")
    func allItemsAggregatesSources() async throws {
        let registry = InboxSourceRegistry()
        let old = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sourceID: "a",
            title: "Old",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let new = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sourceID: "b",
            title: "New",
            body: "body",
            due: nil,
            tags: ["work"],
            createdAt: Date(timeIntervalSince1970: 200)
        )

        await registry.register(RecordingInboxSource(id: "a", items: [old]))
        await registry.register(RecordingInboxSource(id: "b", items: [new]))

        let items = try await registry.allItems()
        #expect(items.map(\.title) == ["New", "Old"])
    }

    @Test("archive and snooze route to the owning source")
    func actionsRouteToSource() async throws {
        let registry = InboxSourceRegistry()
        let source = RecordingInboxSource(id: "tasks.no-date", items: [])
        let item = InboxItem(
            id: UUID(),
            sourceID: "tasks.no-date",
            title: "Buy milk",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 300)
        )
        await registry.register(source)

        try await registry.archive(item)
        try await registry.snooze(item, until: Date(timeIntervalSince1970: 400))

        let events = await source.events
        #expect(events == ["archive:Buy milk", "snooze:Buy milk:400"])
    }

    @Test("allItems caches: a second call without invalidation does not re-query sources")
    func allItemsCachesAcrossCalls() async throws {
        let registry = InboxSourceRegistry()
        let old = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            sourceID: "a",
            title: "Old",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let new = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            sourceID: "b",
            title: "New",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let sourceA = CountingInboxSource(id: "a", items: [old])
        let sourceB = CountingInboxSource(id: "b", items: [new])
        await registry.register(sourceA)
        await registry.register(sourceB)

        let first = try await registry.allItems()
        let second = try await registry.allItems()

        // Identical sorted output served from the cache.
        #expect(first.map(\.id) == second.map(\.id))
        #expect(second.map(\.title) == ["New", "Old"])
        // Each source was queried exactly once — the second call hit the cache.
        #expect(await sourceA.itemsCallCount == 1)
        #expect(await sourceB.itemsCallCount == 1)
    }

    @Test("invalidateCache forces the next allItems to re-query sources")
    func invalidateCacheForcesRequery() async throws {
        let registry = InboxSourceRegistry()
        let item = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            sourceID: "a",
            title: "Only",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let source = CountingInboxSource(id: "a", items: [item])
        await registry.register(source)

        _ = try await registry.allItems()
        await registry.invalidateCache()
        _ = try await registry.allItems()

        #expect(await source.itemsCallCount == 2)
    }

    @Test("cached output is identical to the un-cached sort of scrambled input")
    func cachedOutputMatchesUncachedSort() async throws {
        // Seed sources in scrambled createdAt/title order; the cache must
        // preserve the exact comparator: createdAt desc, then title ascending.
        let alpha = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            sourceID: "a",
            title: "Alpha",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let bravo = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
            sourceID: "a",
            title: "Bravo",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let charlie = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
            sourceID: "b",
            title: "Charlie",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 500)
        )
        let delta = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000034")!,
            sourceID: "b",
            title: "Delta",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        // Scrambled within each source.
        let registry = InboxSourceRegistry()
        await registry.register(CountingInboxSource(id: "a", items: [bravo, alpha]))
        await registry.register(CountingInboxSource(id: "b", items: [delta, charlie]))

        let all = [alpha, bravo, charlie, delta]
        let expected = all.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        // First call computes; second serves the cache. Both equal the
        // reference sort. Expected order: Charlie(500), Alpha(300), Bravo(300), Delta(100).
        let cached = try await registry.allItems()
        let cachedAgain = try await registry.allItems()
        #expect(cached.map(\.id) == expected.map(\.id))
        #expect(cachedAgain.map(\.id) == expected.map(\.id))
        #expect(cached.map(\.title) == ["Charlie", "Alpha", "Bravo", "Delta"])
    }

    @Test("archive throws missingSource when no source matches")
    func archiveThrowsForUnknownSource() async throws {
        let registry = InboxSourceRegistry()
        let item = InboxItem(
            id: UUID(),
            sourceID: "ghost",
            title: "Phantom",
            body: nil,
            due: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 500)
        )

        await #expect(throws: InboxSourceRegistryError.missingSource("ghost")) {
            try await registry.archive(item)
        }
    }
}

private actor RecordingInboxSource: InboxSource {
    let id: String
    let displayName: String
    let iconName: String
    private let storedItems: [InboxItem]
    private(set) var events: [String] = []

    init(id: String, items: [InboxItem]) {
        self.id = id
        self.displayName = id
        self.iconName = "tray"
        self.storedItems = items
    }

    func items() async throws -> [InboxItem] { storedItems }

    func archive(_ item: InboxItem) async throws {
        events.append("archive:\(item.title)")
    }

    func snooze(_ item: InboxItem, until date: Date) async throws {
        events.append("snooze:\(item.title):\(Int(date.timeIntervalSince1970))")
    }
}

/// Counts how many times `items()` is invoked so caching can be proven: a
/// cache hit must NOT re-enter the source, an invalidation MUST re-query.
private actor CountingInboxSource: InboxSource {
    let id: String
    let displayName: String
    let iconName: String
    private let storedItems: [InboxItem]
    private(set) var itemsCallCount = 0

    init(id: String, items: [InboxItem]) {
        self.id = id
        self.displayName = id
        self.iconName = "tray"
        self.storedItems = items
    }

    func items() async throws -> [InboxItem] {
        itemsCallCount += 1
        return storedItems
    }

    func archive(_ item: InboxItem) async throws {}

    func snooze(_ item: InboxItem, until date: Date) async throws {}
}

/// Reports a `count()` without ever materializing `items()`, proving the
/// registry's `totalCount()` uses the cheap count path (no fetch of the list).
private actor CountOnlyInboxSource: InboxSource {
    let id: String
    let displayName: String
    let iconName: String
    private let total: Int
    private(set) var itemsWasMaterialized = false

    init(id: String, count: Int) {
        self.id = id
        self.displayName = id
        self.iconName = "tray"
        self.total = count
    }

    func items() async throws -> [InboxItem] {
        itemsWasMaterialized = true
        return []
    }

    func count() async throws -> Int { total }

    func archive(_ item: InboxItem) async throws {}

    func snooze(_ item: InboxItem, until date: Date) async throws {}
}
