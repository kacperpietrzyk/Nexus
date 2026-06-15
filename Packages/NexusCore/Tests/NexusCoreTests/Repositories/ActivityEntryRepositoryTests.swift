import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("ActivityEntryRepository")
struct ActivityEntryRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([ActivityEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// A strictly increasing clock so `createdAt` ordering is deterministic.
    private final class Tick {
        private var current = Date(timeIntervalSince1970: 1_700_000_000)
        func next() -> Date {
            current = current.addingTimeInterval(60)
            return current
        }
    }

    @MainActor
    @Test("insert persists an append-only event row and stamps the injected clock")
    func insertPersists() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let repo = ActivityEntryRepository(context: context, now: { stamp })
        let itemID = UUID()

        let entry = try repo.insert(itemID: itemID, itemKind: .task, eventKind: .created)
        #expect(entry.itemID == itemID)
        #expect(entry.itemKind == .task)
        #expect(entry.eventKind == .created)
        #expect(entry.createdAt == stamp)

        let fetched = try context.fetch(FetchDescriptor<ActivityEntry>())
        #expect(fetched.count == 1)
    }

    @MainActor
    @Test("entries filters by item id AND kind, newest first")
    func entriesFiltersAndSorts() throws {
        let context = try makeContext()
        let tick = Tick()
        let repo = ActivityEntryRepository(context: context, now: { tick.next() })
        let itemID = UUID()

        try repo.insert(itemID: itemID, itemKind: .task, eventKind: .created)
        try repo.insert(itemID: itemID, itemKind: .task, eventKind: .completed)
        try repo.insert(itemID: UUID(), itemKind: .task, eventKind: .created)  // other item
        try repo.insert(itemID: itemID, itemKind: .project, eventKind: .created)  // same id, other kind

        let entries = try repo.entries(for: itemID, kind: .task)
        #expect(entries.map(\.eventKind) == [.completed, .created])
    }

    @MainActor
    @Test("limit caps the result at the newest entries")
    func limitApplies() throws {
        let context = try makeContext()
        let tick = Tick()
        let repo = ActivityEntryRepository(context: context, now: { tick.next() })
        let itemID = UUID()

        try repo.insert(itemID: itemID, itemKind: .task, eventKind: .created)
        try repo.insert(itemID: itemID, itemKind: .task, eventKind: .workflowChanged)
        try repo.insert(itemID: itemID, itemKind: .task, eventKind: .completed)

        let entries = try repo.entries(for: itemID, kind: .task, limit: 2)
        #expect(entries.map(\.eventKind) == [.completed, .workflowChanged])
    }

    @MainActor
    @Test("payloadJSON round-trips verbatim")
    func payloadRoundTrips() throws {
        let context = try makeContext()
        let repo = ActivityEntryRepository(context: context)
        let itemID = UUID()

        try repo.insert(
            itemID: itemID,
            itemKind: .task,
            eventKind: .workflowChanged,
            payloadJSON: "{\"old\":\"todo\",\"new\":\"inProgress\"}"
        )

        let entries = try repo.entries(for: itemID, kind: .task)
        #expect(entries.first?.payloadJSON == "{\"old\":\"todo\",\"new\":\"inProgress\"}")
    }
}
