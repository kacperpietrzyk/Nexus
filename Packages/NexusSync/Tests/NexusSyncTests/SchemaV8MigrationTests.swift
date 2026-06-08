import Foundation
import NexusCore
import SwiftData
import Testing
@testable import NexusSync

@Suite struct SchemaV8MigrationTests {
    @Test func v8AddsCommentToV7Models() {
        #expect(NexusSchemaV8.models.count == NexusSchemaV7.models.count + 1)
        #expect(NexusSchemaV8.models.contains { $0 == Comment.self })
    }

    @Test func migrationPlanIncludesV8Stage() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV8.self })
    }

    /// `Comment` is a synced partition: task/project comment threads must mirror
    /// through CloudKit private DB with the user-visible item they are attached to,
    /// not stay device-local with diagnostics/catalog metadata.
    @Test func commentIsASyncedPartitionNotLocalOnly() {
        let partitions = NexusModelContainer.modelPartitions(extraModels: [StubSyncedExtra.self])
        #expect(partitions.syncedModels.contains { String(describing: $0) == "Comment" })
        #expect(!partitions.localOnlyModels.contains { String(describing: $0) == "Comment" })
    }

    @Test func taskWithRemindersPersistsInV8Container() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(NexusSchemaV8.models, version: NexusSchemaV8.versionIdentifier),
            configurations: config
        )
        let context = ModelContext(container)
        let task = TaskItem(title: "remind me")
        task.reminders = [.relative(offset: -1800, anchor: .due)]
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(fetched.first?.reminders == [.relative(offset: -1800, anchor: .due)])
    }

    @Test func latestSchemaPreservesV8CommentAndReminderAdditions() throws {
        #expect(NexusSchemaV12.models.contains { $0 == Comment.self })

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(NexusSchemaV12.models, version: NexusSchemaV12.versionIdentifier),
            configurations: config
        )
        let context = ModelContext(container)
        let task = TaskItem(title: "latest reminder")
        task.reminders = [.absolute(Date(timeIntervalSince1970: 1_700_000_000))]
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(fetched.first?.reminders == [.absolute(Date(timeIntervalSince1970: 1_700_000_000))])
    }

    @MainActor
    @Test func splitContainerInfersV7ToV8LightweightExpansionWithoutDataLoss() throws {
        let storeURL = temporaryStoreURL(prefix: "nexus-v7-to-v8-split-inference")
        defer {
            cleanupStores(at: [storeURL, NexusModelContainer.localOnlyStoreURL(for: storeURL)])
        }

        let seeded = try seedV7ProjectSectionTaskStore(at: storeURL)

        let container = try NexusModelContainer.make(
            environment: V8LocalOnlySplitTestEnvironment(),
            fileURL: storeURL
        )
        let context = ModelContext(container)

        let projects = try context.fetch(FetchDescriptor<Project>())
        let sections = try context.fetch(FetchDescriptor<Section>())
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let task = try #require(tasks.first { $0.id == seeded.taskID })

        #expect(projects.first { $0.id == seeded.projectID }?.name == "CyberLab")
        #expect(sections.first { $0.id == seeded.sectionID }?.projectID == seeded.projectID)
        #expect(sections.first { $0.id == seeded.sectionID }?.name == "Later")
        #expect(task.title == "pre-V8 task")
        #expect(task.projectID == seeded.projectID)
        #expect(task.sectionID == seeded.sectionID)
        #expect(task.tags == ["todoist"])

        let comment = Comment(itemID: task.id, itemKind: ItemKind.task, body: "synced note")
        context.insert(comment)
        task.reminders = [.relative(offset: -900, anchor: .due)]
        try context.save()

        #expect(comment.body == "synced note")
        #expect(task.reminders == [.relative(offset: -900, anchor: .due)])
    }
}

private struct V8SeededIDs {
    let projectID: UUID
    let sectionID: UUID
    let taskID: UUID
}

private struct V8LocalOnlySplitTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"
}

private func temporaryStoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

@MainActor
private func seedV7ProjectSectionTaskStore(at url: URL) throws -> V8SeededIDs {
    let schema = Schema(versionedSchema: NexusSchemaV7.self)
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ]
    )
    let context = ModelContext(container)
    let project = Project(name: "CyberLab", color: "emerald")
    let section = Section(projectID: project.id, name: "Later", orderIndex: 2)
    let task = TaskItem(
        title: "pre-V8 task",
        dueAt: Date(timeIntervalSince1970: 1_800_000_000),
        tags: ["todoist"],
        projectID: project.id,
        sectionID: section.id
    )
    context.insert(project)
    context.insert(section)
    context.insert(task)
    try context.save()
    return V8SeededIDs(projectID: project.id, sectionID: section.id, taskID: task.id)
}

private func cleanupStores(at urls: [URL]) {
    for url in urls {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
    }
}
