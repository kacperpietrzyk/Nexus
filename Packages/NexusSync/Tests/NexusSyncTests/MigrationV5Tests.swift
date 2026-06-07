import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite("Migration V4 → V5")
struct MigrationV5Tests {
    @MainActor
    @Test("V4 store migrates to V5 with nil endAt")
    func migratesV4StoreWithNilEndAt() throws {
        let url = tempStoreURL(prefix: "nexus-v4-to-v5")
        defer { cleanupStore(at: url) }

        let metadata = Data(#"{"source":"todoist","id":"8237162"}"#.utf8)
        try seedV4Store(at: url, metadata: metadata)

        let context = try makeV5Context(url: url)

        let fetched = try context.fetch(FetchDescriptor<NexusSchemaV5.TaskItem>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Imported before endAt")
        #expect(fetched.first?.endAt == nil)
        #expect(fetched.first?.externalSourceID == "todoist:8237162")
        #expect(fetched.first?.externalSourceMetadata == metadata)
    }

    @MainActor
    @Test("V5 schema accepts TaskItem with nil endAt")
    func acceptsNilEndAtInFreshV5Store() throws {
        let context = try makeV5Context()
        let dueAt = Date(timeIntervalSince1970: 1_778_155_200)
        let startAt = Date(timeIntervalSince1970: 1_778_158_800)
        let task = NexusSchemaV5.TaskItem(title: "Fresh open-ended task", dueAt: dueAt, startAt: startAt, endAt: nil)
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<NexusSchemaV5.TaskItem>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.dueAt == dueAt)
        #expect(fetched.first?.startAt == startAt)
        #expect(fetched.first?.endAt == nil)
    }

    @MainActor
    @Test("V5 schema persists TaskItem endAt when set")
    func persistsSetEndAt() throws {
        let context = try makeV5Context()
        let startAt = Date(timeIntervalSince1970: 1_778_158_800)
        let endAt = Date(timeIntervalSince1970: 1_778_162_400)
        let task = NexusSchemaV5.TaskItem(title: "Timed block", startAt: startAt, endAt: endAt)
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<NexusSchemaV5.TaskItem>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.startAt == startAt)
        #expect(fetched.first?.endAt == endAt)
    }

    @Test("migration plan exposes V5 schema and V4 to V5 stage")
    func planExposesV5Stage() {
        let names = NexusMigrationPlan.schemas.map { String(describing: $0) }

        #expect(names.contains("NexusSchemaV5"))
        #expect(NexusMigrationPlan.stages.count == 9)
    }
}

@MainActor
private func seedV4Store(at url: URL, metadata: Data) throws {
    let schema = Schema(versionedSchema: NexusSchemaV4.self)
    let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [config]
    )
    let context = ModelContext(container)
    let task = NexusSchemaV4.TaskItem(title: "Imported before endAt")
    task.externalSourceID = "todoist:8237162"
    task.externalSourceMetadata = metadata
    context.insert(task)
    try context.save()
}

@MainActor
private func makeV5Context(url: URL? = nil) throws -> ModelContext {
    let schema = Schema(versionedSchema: NexusSchemaV5.self)
    let config =
        if let url {
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [config]
    )
    return ModelContext(container)
}

private func tempStoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupStore(at url: URL) {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: url)
    try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
}
