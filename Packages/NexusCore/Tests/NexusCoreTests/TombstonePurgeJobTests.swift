import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
@Test func tombstonePurgeJob_purgesOlderThanRetention() async throws {
    let schema = Schema([DebugItem.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let oldItem = DebugItem(title: "old")
    oldItem.deletedAt = Date.now.addingTimeInterval(-60 * 60 * 24 * 60)  // 60 days
    let recentItem = DebugItem(title: "recent")
    recentItem.deletedAt = Date.now.addingTimeInterval(-60 * 60 * 24 * 5)  // 5 days
    let alive = DebugItem(title: "alive")
    context.insert(oldItem)
    context.insert(recentItem)
    context.insert(alive)
    try context.save()

    let job = TombstonePurgeJob.make(
        container: container,
        retention: 60 * 60 * 24 * 30,  // 30 days
        linkableTypes: [DebugItem.self]
    )
    try await job.run(.now)

    let remaining = try context.fetch(FetchDescriptor<DebugItem>())
    let titles = Set(remaining.map(\.title))
    #expect(titles == ["recent", "alive"])
}
