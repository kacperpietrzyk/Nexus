import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

/// V9 -> V10 migration: additive registration of the `ScheduledBlock` scheduler
/// entity plus the additive `TaskItem.estimatedDurationSeconds` /
/// `TaskItem.durationSourceRaw` fields (Calendar / Motion-AI module, spec §3/§4.1/§5).
///
/// The whole V9 -> V10 delta is lightweight-additive: a shipped-V9 on-disk store
/// physically lacks the `ScheduledBlock` table and the two duration columns; the
/// V10 build's lightweight inference adds all three in one pass. There is no data
/// move, so unlike V9 there is no marker-gated post-open code to exercise — the
/// tests prove (1) the schema shape, (2) `ScheduledBlock` is insertable on a fresh
/// V10 store, and (3) a real on-disk V9 store with a duration-bearing `TaskItem`
/// and a composition-time synced extra survives the reopen through the REAL
/// production split container with no data loss and accepts a new `ScheduledBlock`.
@Suite struct SchemaV10MigrationTests {
    // MARK: - Schema shape

    @Test func v10AddsScheduledBlockToV9Models() {
        #expect(NexusSchemaV10.models.count == NexusSchemaV9.models.count + 1)
        #expect(NexusSchemaV10.models.contains { $0 == ScheduledBlock.self })
    }

    @Test func v10VersionIsHigherThanV9() {
        #expect(NexusSchemaV10.versionIdentifier > NexusSchemaV9.versionIdentifier)
    }

    @Test func migrationPlanIncludesV10Schema() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV10.self })
    }

    /// `ScheduledBlock` is a SYNCED partition (spec §3/§4.1): blocks mirror to the
    /// CloudKit private DB so accepted/proposed schedules follow the user across
    /// devices. It must NOT slip into `localOnlyBaseline`. The on-disk crown-jewel
    /// test runs with CloudKit off (both partitions local), so it cannot tell the
    /// two apart — this is the one discriminating check that pins the requirement.
    @Test func scheduledBlockIsASyncedPartitionNotLocalOnly() {
        let partitions = NexusModelContainer.modelPartitions(extraModels: [StubSyncedExtra.self])
        #expect(partitions.syncedModels.contains { String(describing: $0) == "ScheduledBlock" })
        #expect(!partitions.localOnlyModels.contains { String(describing: $0) == "ScheduledBlock" })
    }

    /// The V9 -> V10 stage is lightweight-additive (ScheduledBlock table + two
    /// additive `TaskItem` columns). It MUST stay `.lightweight`: the production
    /// split container drops the plan and relies on inference, so a `.custom`
    /// stage here would never run for real users.
    @Test func v9ToV10StageIsLightweight() {
        let v9ToV10 = NexusMigrationPlan.stages
            .map { String(describing: $0) }
            .filter { $0.contains("V9") && $0.contains("V10") }
        #expect(v9ToV10.count == 1)
        #expect(v9ToV10.allSatisfy { $0.contains("lightweight") })
    }

    // MARK: - Fresh V10 store

    /// A fresh V10 store accepts `ScheduledBlock` inserts and round-trips a
    /// `TaskItem` carrying the additive duration fields.
    @Test func freshV10StoreAllowsScheduledBlockInsertsAndDurationFields() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV10.models, version: NexusSchemaV10.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let task = TaskItem(
            title: "Estimated task",
            estimatedDurationSeconds: 5_400,
            durationSource: .explicit
        )
        context.insert(task)
        let block = ScheduledBlock(
            taskID: task.id,
            start: Date(timeIntervalSince1970: 1_780_000_000),
            end: Date(timeIntervalSince1970: 1_780_005_400),
            title: "Estimated task"
        )
        context.insert(block)
        try context.save()

        let blocks = try context.fetch(FetchDescriptor<ScheduledBlock>())
        #expect(blocks.count == 1)
        let fetchedBlock = try #require(blocks.first)
        #expect(fetchedBlock.taskID == task.id)
        #expect(fetchedBlock.kind == .scheduledBlock)
        #expect(fetchedBlock.status == .proposed)
        #expect(fetchedBlock.origin == .auto)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let fetchedTask = try #require(tasks.first)
        #expect(fetchedTask.estimatedDurationSeconds == 5_400)
        #expect(fetchedTask.durationSource == .explicit)
    }

    /// Soft-delete works (consistent with the other models): a deleted block
    /// carries `deletedAt` and remains physically present (filtered by callers,
    /// not purged).
    @Test func scheduledBlockSoftDeleteSetsDeletedAt() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV10.models, version: NexusSchemaV10.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let block = ScheduledBlock(
            taskID: UUID(),
            start: .now,
            end: .now.addingTimeInterval(1_800)
        )
        #expect(block.deletedAt == nil)
        context.insert(block)
        try context.save()

        block.deletedAt = Date(timeIntervalSince1970: 1_780_100_000)
        try context.save()

        let blocks = try context.fetch(FetchDescriptor<ScheduledBlock>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.deletedAt == Date(timeIntervalSince1970: 1_780_100_000))
    }

    // MARK: - Production split-container path (on-disk, crown jewel)

    /// THE deliverable. Seeds a real on-disk store stamped at V9 holding a
    /// `TaskItem` with the additive duration fields populated and a
    /// composition-time synced extra (`StubSyncedExtra`, the Meeting stand-in),
    /// then reopens through the REAL production entry `NexusModelContainer.make`
    /// (the split synced + local-only container that DROPS the migration plan and
    /// relies on lightweight inference). Proves:
    ///   1. the duration-bearing `TaskItem` survived with its values intact (the
    ///      additive columns inferred, no data loss),
    ///   2. a new `ScheduledBlock` is insertable on the migrated store,
    ///   3. the Meeting stand-in row SURVIVED (no destructive migration),
    ///   4. no pre-existing rows were lost.
    @MainActor
    @Test func splitContainerInfersV9ToV10AdditiveExpansionOnDisk() throws {
        let storeURL = temporaryV10StoreURL(prefix: "nexus-v9-to-v10-additive")
        defer { cleanupV10Stores(at: storeURL) }
        // V9's body -> Note conversion is marker-gated per store path; this fresh
        // temp path is never marked, so `make()` runs the (no-op for our seed)
        // conversion on first open. Clear it on exit so a reused tmpdir path never
        // carries the marker into another run.
        defer {
            UserDefaults.standard.removeObject(
                forKey: NexusModelContainer.taskBodyToNoteMigrationCompletionKey(for: storeURL)
            )
        }

        let taskID = UUID()
        try seedV9SyncedStore(at: storeURL, taskID: taskID)

        // Reopen through the REAL production entry. `make()` emits the split
        // synced + local-only container (dropping the plan → lightweight
        // inference adds the ScheduledBlock table + the two TaskItem columns).
        let container = try NexusModelContainer.make(
            environment: V10MigrationTestEnvironment(),
            fileURL: storeURL,
            extraModels: [StubSyncedExtra.self]
        )
        let context = ModelContext(container)

        // (1) Duration-bearing task survived with intact values.
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(tasks.count == 1)
        let task = try #require(tasks.first { $0.id == taskID })
        #expect(task.title == "Has duration")
        #expect(task.estimatedDurationSeconds == 3_600)
        #expect(task.durationSource == .explicit)

        // (2) ScheduledBlock is insertable on the migrated store.
        let block = ScheduledBlock(
            taskID: taskID,
            start: Date(timeIntervalSince1970: 1_780_200_000),
            end: Date(timeIntervalSince1970: 1_780_203_600),
            title: "Has duration"
        )
        context.insert(block)
        try context.save()
        let blocks = try context.fetch(FetchDescriptor<ScheduledBlock>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.taskID == taskID)

        // (3) Meeting stand-in survived (no destructive migration).
        let survivors = try context.fetch(FetchDescriptor<StubSyncedExtra>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.label == "keep me across V10")
    }
}

// MARK: - Fixtures

private struct V10MigrationTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"
}

/// Seeds a synced (main) store stamped at V9 with one `TaskItem` carrying the
/// additive duration fields and a composition-time synced extra entity. Mirrors
/// what the split container physically writes to the main store URL before V10
/// lands.
@MainActor
private func seedV9SyncedStore(at url: URL, taskID: UUID) throws {
    let schema = NexusSchemaV9.schema(extraModels: [StubSyncedExtra.self])
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ]
    )
    let context = ModelContext(container)

    let task = TaskItem(
        title: "Has duration",
        estimatedDurationSeconds: 3_600,
        durationSource: .explicit
    )
    task.id = taskID
    context.insert(task)

    context.insert(StubSyncedExtra(label: "keep me across V10"))
    try context.save()
}

private func temporaryV10StoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupV10Stores(at storeURL: URL) {
    let urls = [storeURL, NexusModelContainer.localOnlyStoreURL(for: storeURL)]
    for url in urls {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
    }
}
