import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("ByTagQuery")
struct ByTagQueryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("matches tags case-insensitively and excludes closed rows")
    func matches() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "w", tags: ["work"]))
        context.insert(TaskItem(title: "we", tags: ["work", "email"]))
        context.insert(TaskItem(title: "p", tags: ["personal"]))
        let done = TaskItem(title: "d", tags: ["work"])
        done.statusRaw = TaskStatus.done.rawValue
        context.insert(done)
        try context.save()

        let titles = try ByTagQuery().tasks(withTag: " WORK ")
            .apply(in: context)
            .map(\.title)
            .sorted()
        #expect(titles == ["w", "we"])
    }
}
