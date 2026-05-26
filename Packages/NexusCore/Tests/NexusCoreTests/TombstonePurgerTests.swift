import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Test func tombstonePurger_default_retainsThirtyDays() {
    #expect(TombstonePurger.defaultRetention == 60 * 60 * 24 * 30)
}

@MainActor
@Test func tombstonePurger_purges_oldDebugItems() async throws {
    let container = try makeContainer()
    try await seedTombstones(container: container, ages: [TimeInterval(60 * 60 * 24 * 31), TimeInterval(60 * 60 * 24 * 5)])

    let purger = TombstonePurger(modelContainer: container)
    let purged = try await purger.purge(
        olderThan: TombstonePurger.defaultRetention,
        now: .now,
        types: [DebugItem.self]
    )
    #expect(purged == 1)

    let context = ModelContext(container)
    let remaining = try context.fetch(FetchDescriptor<DebugItem>())
    #expect(remaining.count == 1)
    #expect(remaining.first?.deletedAt != nil)  // the 5-day-old tombstone, still within retention
}

@MainActor
@Test func tombstonePurger_doesNotTouchLiveItems() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let item = DebugItem(title: "alive")
    context.insert(item)
    try context.save()
    let itemID = item.id

    let purger = TombstonePurger(modelContainer: container)
    let purged = try await purger.purge(olderThan: 0, now: .now, types: [DebugItem.self])
    #expect(purged == 0)

    let remaining = try context.fetch(FetchDescriptor<DebugItem>())
    #expect(remaining.count == 1)
    #expect(remaining.first?.id == itemID)
}

@MainActor
@Test func tombstonePurger_purges_taskItems() async throws {
    let schema = Schema([TaskItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let stale = TaskItem(title: "stale")
    stale.deletedAt = Date.now.addingTimeInterval(-60 * 60 * 24 * 60)
    let fresh = TaskItem(title: "fresh")
    fresh.deletedAt = Date.now.addingTimeInterval(-60 * 60 * 24)
    context.insert(stale)
    context.insert(fresh)
    try context.save()

    let purger = TombstonePurger(modelContainer: container)
    let purged = try await purger.purge(
        olderThan: 60 * 60 * 24 * 30,
        now: .now,
        types: [TaskItem.self]
    )
    #expect(purged == 1)
    let remaining = try ModelContext(container).fetch(FetchDescriptor<TaskItem>())
    #expect(remaining.map(\.title) == ["fresh"])
}

@MainActor
@Test func tombstonePurger_purges_multipleTypes() async throws {
    let schema = Schema([TaskItem.self, DebugItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let task = TaskItem(title: "task")
    task.deletedAt = Date.now.addingTimeInterval(-60 * 60 * 24 * 60)
    let debug = DebugItem(title: "debug")
    debug.deletedAt = Date.now.addingTimeInterval(-60 * 60 * 24 * 60)
    context.insert(task)
    context.insert(debug)
    try context.save()

    let purger = TombstonePurger(modelContainer: container)
    let purged = try await purger.purge(
        olderThan: 60 * 60 * 24 * 30,
        now: .now,
        types: [TaskItem.self, DebugItem.self]
    )
    #expect(purged == 2)
}

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Link.self, DebugItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func seedTombstones(container: ModelContainer, ages: [TimeInterval]) async throws {
    let context = ModelContext(container)
    let now = Date.now
    for age in ages {
        let item = DebugItem(title: "tombstone-\(age)")
        item.deletedAt = now.addingTimeInterval(-age)
        item.updatedAt = item.deletedAt!
        context.insert(item)
    }
    try context.save()
}
