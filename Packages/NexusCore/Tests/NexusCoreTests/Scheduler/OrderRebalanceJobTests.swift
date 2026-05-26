import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("OrderRebalanceJob")
struct OrderRebalanceJobTests {

    @Test("renumbers tasks 1.0, 2.0, 3.0 by ascending current orderIndex")
    @MainActor
    func renumbersByAscendingIndex() async throws {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let a = TaskItem(title: "a", orderIndex: 1.5)
        let b = TaskItem(title: "b", orderIndex: 1.500001)
        let c = TaskItem(title: "c", orderIndex: 2.0)
        context.insert(a)
        context.insert(b)
        context.insert(c)
        try context.save()

        let job = OrderRebalanceJob.makeJob(containerProvider: { container })
        try await job.run(.now)

        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        let renumbered = try context.fetch(descriptor)
        #expect(renumbered.compactMap(\.orderIndex) == [1.0, 2.0, 3.0])
    }

    @Test("ignores tasks with nil orderIndex")
    @MainActor
    func ignoresNilOrderIndex() async throws {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        context.insert(TaskItem(title: "ordered", orderIndex: 1.0))
        context.insert(TaskItem(title: "no-order"))
        try context.save()

        let job = OrderRebalanceJob.makeJob(containerProvider: { container })
        try await job.run(.now)

        let descriptor = FetchDescriptor<TaskItem>()
        let all = try context.fetch(descriptor)
        let ordered = all.filter { $0.orderIndex != nil }
        #expect(ordered.count == 1)
        #expect(ordered.first?.orderIndex == 1.0)
    }
}
