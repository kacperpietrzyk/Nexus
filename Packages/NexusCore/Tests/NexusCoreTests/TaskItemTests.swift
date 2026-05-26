import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItem")
struct TaskItemTests {
    @Test("init with title sets defaults")
    func defaults() {
        let task = TaskItem(title: "Buy milk")
        #expect(task.title == "Buy milk")
        #expect(task.body.isEmpty)
        #expect(task.dueAt == nil)
        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.priorityRaw == TaskPriority.none.rawValue)
        #expect(task.tags.isEmpty)
        #expect(task.recurrenceRule == nil)
        #expect(task.recurrenceParentId == nil)
        #expect(task.parentTaskID == nil)
        #expect(task.deadlineAt == nil)
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)
        #expect(task.kind == .task)
    }

    @Test("Searchable combines title body and tags")
    func searchableText() {
        let task = TaskItem(title: "Buy milk", body: "From Lidl", tags: ["shopping", "weekly"])
        #expect(task.searchableText.contains("Buy milk"))
        #expect(task.searchableText.contains("From Lidl"))
        #expect(task.searchableText.contains("shopping weekly"))
    }

    @MainActor
    @Test("can be inserted into in-memory ModelContainer")
    func insertable() throws {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.insert(TaskItem(title: "first"))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "first")
    }

    @Test("init can override important fields")
    func initOverrides() {
        let id = UUID()
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = Date(timeIntervalSince1970: 1_800_086_400)
        let parent = UUID()
        let project = UUID()
        let section = UUID()
        let task = TaskItem(
            id: id,
            title: "Reply",
            body: "ASAP",
            dueAt: due,
            deadlineAt: deadline,
            priority: .high,
            status: .snoozed,
            tags: ["work"],
            recurrenceRule: "FREQ=WEEKLY;BYDAY=MO",
            parentTaskID: parent,
            projectID: project,
            sectionID: section
        )
        #expect(task.id == id)
        #expect(task.dueAt == due)
        #expect(task.deadlineAt == deadline)
        #expect(task.priority == .high)
        #expect(task.status == .snoozed)
        #expect(task.recurrenceRule == "FREQ=WEEKLY;BYDAY=MO")
        #expect(task.parentTaskID == parent)
        #expect(task.projectID == project)
        #expect(task.sectionID == section)
    }
}

@Suite("TaskItemExternalSourceTests")
struct TaskItemExternalSourceTests {
    @Test("external source fields default to nil")
    func externalSourceDefaults() {
        let task = TaskItem(title: "Imported later")

        #expect(task.externalSourceID == nil)
        #expect(task.externalSourceMetadata == nil)
    }

    @Test("external source fields can store source id and metadata")
    func externalSourceFields() {
        let task = TaskItem(title: "Imported task")
        let metadata = Data(#"{"id":"8237162","source":"todoist"}"#.utf8)

        task.externalSourceID = "todoist:8237162"
        task.externalSourceMetadata = metadata

        #expect(task.externalSourceID == "todoist:8237162")
        #expect(task.externalSourceMetadata == metadata)
    }
}
