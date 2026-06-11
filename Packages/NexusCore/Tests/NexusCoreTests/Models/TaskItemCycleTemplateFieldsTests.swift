import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItem cycle/template fields (V13)")
struct TaskItemCycleTemplateFieldsTests {
    @Test("defaults are nil cycle and non-template")
    func defaultsAreNilAndFalse() {
        let task = TaskItem(title: "plain")
        #expect(task.cycleID == nil)
        #expect(!task.isTemplate)
    }

    @Test("init accepts trailing cycleID/isTemplate parameters")
    func initAcceptsTrailingParameters() {
        let cycleID = UUID()
        let task = TaskItem(title: "templated", cycleID: cycleID, isTemplate: true)
        #expect(task.cycleID == cycleID)
        #expect(task.isTemplate)
    }

    @MainActor
    @Test("new fields round-trip through an in-memory store")
    func roundTripsThroughStore() throws {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let cycleID = UUID()
        context.insert(TaskItem(title: "plain"))
        context.insert(TaskItem(title: "in cycle", cycleID: cycleID, isTemplate: true))
        try context.save()

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let plain = try #require(tasks.first { $0.title == "plain" })
        #expect(plain.cycleID == nil)
        #expect(!plain.isTemplate)

        let assigned = try #require(tasks.first { $0.title == "in cycle" })
        #expect(assigned.cycleID == cycleID)
        #expect(assigned.isTemplate)
    }
}
