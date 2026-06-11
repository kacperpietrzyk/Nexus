import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("Cycle")
struct CycleTests {
    @Test("CycleStatus raw values are pinned — they land in CloudKit, never rename after introduction")
    func statusRawValuesAreStable() {
        #expect(CycleStatus.upcoming.rawValue == "upcoming")
        #expect(CycleStatus.active.rawValue == "active")
        #expect(CycleStatus.completed.rawValue == "completed")
        #expect(CycleStatus.allCases == [.upcoming, .active, .completed])
    }

    @Test("CycleStatus is Codable round-trip")
    func statusIsCodable() throws {
        for status in CycleStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(CycleStatus.self, from: encoded)
            #expect(decoded == status)
        }
    }

    @Test("init sets kind, defaults, and timestamps")
    func initSetsDefaults() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_600_000)
        let cycle = Cycle(name: "Sprint 1", startAt: start, endAt: end)

        #expect(cycle.kind == .cycle)
        #expect(cycle.name == "Sprint 1")
        #expect(cycle.startAt == start)
        #expect(cycle.endAt == end)
        #expect(cycle.statusRaw == "upcoming")
        #expect(cycle.status == .upcoming)
        #expect(cycle.deletedAt == nil)
        #expect(cycle.createdAt == cycle.updatedAt)
    }

    @Test("title is a settable view over name (Project precedent — Linkable conformance)")
    func titleMirrorsName() {
        let cycle = Cycle(name: "Sprint 1", startAt: .now, endAt: .now)
        #expect(cycle.title == "Sprint 1")
        cycle.title = "Sprint 2"
        #expect(cycle.name == "Sprint 2")
    }

    @Test("unknown statusRaw falls back to .upcoming")
    func unknownStatusFallsBack() {
        let cycle = Cycle(name: "S", startAt: .now, endAt: .now)
        cycle.statusRaw = "future-status"
        #expect(cycle.status == .upcoming)
    }

    @MainActor
    @Test("persists and round-trips in an in-memory store")
    func persistsInStore() throws {
        let schema = Schema([Cycle.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let cycle = Cycle(name: "Sprint 1", startAt: .now, endAt: .now, status: .active)
        context.insert(cycle)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Cycle>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.status == .active)
        #expect(fetched.first?.kind == .cycle)
    }
}
