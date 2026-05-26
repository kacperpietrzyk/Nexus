import Foundation
import InboxShell
import Testing

@Suite("InboxSourceRegistry")
struct InboxSourceRegistryTests {

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
