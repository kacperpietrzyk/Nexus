import Foundation
import Testing

@testable import NexusAgent

@Suite
struct AgentScheduleStoreTests {
    @Test func scheduleStoreListReturnsAll() throws {
        let context = try AgentTestSupport.makeContext()
        let store = AgentScheduleStore(context: context)

        _ = try store.create(name: "Morning Brief", cronExpression: "0 8 * * *", prompt: "...")
        _ = try store.create(
            name: "Evening Plan",
            cronExpression: "0 18 * * *",
            prompt: "...",
            enabled: false
        )

        let all = try store.allActive()

        #expect(all.count == 2)
        #expect(all.contains { $0.enabled == false })
    }

    @Test func scheduleStoreSortsByName() throws {
        let context = try AgentTestSupport.makeContext()
        let store = AgentScheduleStore(context: context)

        _ = try store.create(name: "Morning Brief", cronExpression: "0 8 * * *", prompt: "...")
        _ = try store.create(name: "Evening Plan", cronExpression: "0 18 * * *", prompt: "...")

        let names = try store.allActive().map(\.name)

        #expect(names == ["Evening Plan", "Morning Brief"])
    }

    @Test func scheduleStoreSetEnabledUpdatesExistingSchedule() throws {
        let context = try AgentTestSupport.makeContext()
        let store = AgentScheduleStore(context: context)
        let id = try store.create(name: "Morning Brief", cronExpression: "0 8 * * *", prompt: "...")
        let created = try #require(try store.get(id: id))
        let previousUpdatedAt = created.updatedAt

        try store.setEnabled(false, id: id)

        let updated = try #require(try store.get(id: id))
        #expect(updated.enabled == false)
        #expect(updated.updatedAt >= previousUpdatedAt)
    }

    @Test func scheduleStoreSetEnabledMissingIDIsNoop() throws {
        let context = try AgentTestSupport.makeContext()
        let store = AgentScheduleStore(context: context)

        try store.setEnabled(false, id: UUID())

        #expect(try store.allActive().isEmpty)
    }
}
