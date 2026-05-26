import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Test func modelPartitionsKeepConflictLogLocalOnlyByDefault() {
    let partitions = NexusModelContainer.modelPartitions()

    #expect(modelNames(partitions.localOnlyModels) == ["ConflictLog"])
    #expect(!modelNames(partitions.syncedModels).contains("ConflictLog"))
    #expect(modelNames(partitions.containerModels).contains("ConflictLog"))
}

@Test func modelPartitionsIgnoreBaselineSyncedModelsInLocalOnlyExtras() {
    let partitions = NexusModelContainer.modelPartitions(localOnlyExtraModels: [
        TaskItem.self,
        Link.self,
        ConflictLog.self,
    ])

    #expect(modelNames(partitions.localOnlyModels) == ["ConflictLog"])
    #expect(modelNames(partitions.syncedModels).contains("TaskItem"))
    #expect(modelNames(partitions.syncedModels).contains("Link"))
}

@Test func cloudEnabledConfigurationPlanSplitsSyncedAndLocalOnlyStores() throws {
    let storeURL = temporaryStoreURL(prefix: "nexus-local-only-config")
    let plan = NexusModelContainer.makeConfigurationPlan(
        isStoredInMemoryOnly: false,
        storeURL: storeURL,
        cloudKitDatabase: .private("iCloud.com.kacperpietrzyk.Nexus")
    )

    let syncedConfiguration = try #require(
        plan.configurations.first { $0.name == NexusModelContainer.syncedConfigurationName }
    )
    let localOnlyConfiguration = try #require(
        plan.configurations.first { $0.name == NexusModelContainer.localOnlyConfigurationName }
    )

    #expect(syncedConfiguration.url == storeURL)
    #expect(localOnlyConfiguration.url.path == storeURL.path + "-local")
    #expect(isPrivateCloudKitDatabase(syncedConfiguration.cloudKitDatabase))
    #expect(isNoCloudKitDatabase(localOnlyConfiguration.cloudKitDatabase))
    #expect(entityNames(in: syncedConfiguration.schema).contains("TaskItem"))
    #expect(!entityNames(in: syncedConfiguration.schema).contains("ConflictLog"))
    #expect(entityNames(in: localOnlyConfiguration.schema) == ["ConflictLog"])
    #expect(entityNames(in: plan.containerSchema).contains("ConflictLog"))
    #expect(entityNames(in: plan.containerSchema).contains("TaskItem"))
}

@Test func migrateStoreFamiliesCopiesMainAndLocalOnlySidecars() throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.store")
    let destination = dir.appendingPathComponent("nested/destination.store")
    let sourceLocalOnly = NexusModelContainer.localOnlyStoreURL(for: source)
    let destinationLocalOnly = NexusModelContainer.localOnlyStoreURL(for: destination)

    try writeStoreFamilyMarker("main", to: source)
    try writeStoreFamilyMarker("local", to: sourceLocalOnly)

    let result = try NexusModelContainer.migrateStoreFamiliesIfNeeded(
        from: source,
        to: destination
    )

    #expect(result.main == .copiedToMissingDestination)
    #expect(result.localOnly == .copiedToMissingDestination)
    #expect(try String(contentsOf: destination, encoding: .utf8) == "main-primary")
    #expect(try String(contentsOf: destination.storeSidecarURL(suffix: "-wal"), encoding: .utf8) == "main-wal")
    #expect(try String(contentsOf: destination.storeSidecarURL(suffix: "-shm"), encoding: .utf8) == "main-shm")
    #expect(try String(contentsOf: destinationLocalOnly, encoding: .utf8) == "local-primary")
    #expect(try String(contentsOf: destinationLocalOnly.storeSidecarURL(suffix: "-wal"), encoding: .utf8) == "local-wal")
    #expect(try String(contentsOf: destinationLocalOnly.storeSidecarURL(suffix: "-shm"), encoding: .utf8) == "local-shm")
}

@MainActor
@Test func onDiskContainerPersistsSyncedAndLocalOnlyBaselineModels() throws {
    let storeURL = temporaryStoreURL(prefix: "nexus-local-only-persistence")
    defer { cleanupStores(at: [storeURL, URL(fileURLWithPath: storeURL.path + "-local")]) }

    let container = try NexusModelContainer.make(
        environment: LocalOnlySplitTestEnvironment(),
        fileURL: storeURL
    )
    let context = ModelContext(container)
    let task = TaskItem(title: "Synced model")
    let conflict = ConflictLog(
        itemKind: .task,
        itemID: task.id,
        resolution: .lastWriteWins,
        summary: "Local diagnostic"
    )

    context.insert(task)
    context.insert(conflict)
    try context.save()

    #expect(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title).contains("Synced model"))
    #expect(try context.fetch(FetchDescriptor<ConflictLog>()).map(\.summary).contains("Local diagnostic"))
}

@MainActor
@Test func splitContainerBackfillsLegacyConflictLogsFromMonolithicStore() throws {
    let storeURL = temporaryStoreURL(prefix: "nexus-legacy-conflict-backfill")
    defer { cleanupStores(at: [storeURL, NexusModelContainer.localOnlyStoreURL(for: storeURL)]) }
    let conflictID = UUID()
    let itemID = UUID()

    try makeLegacyMonolithicV6Store(
        at: storeURL,
        conflictID: conflictID,
        itemID: itemID,
        summary: "legacy conflict"
    )

    let container = try NexusModelContainer.make(
        environment: LocalOnlySplitTestEnvironment(),
        fileURL: storeURL
    )
    let context = ModelContext(container)
    let conflicts = try context.fetch(FetchDescriptor<ConflictLog>())

    #expect(conflicts.map(\.id).contains(conflictID))
    #expect(conflicts.first { $0.id == conflictID }?.itemID == itemID)
    #expect(conflicts.first { $0.id == conflictID }?.summary == "legacy conflict")
}

/// Exercises the production migration path for V6 -> V7. The real app always
/// opens via `NexusModelContainer.make(...)`, which splits synced + local-only
/// into two `ModelConfiguration`s. That makes `makeContainer`'s
/// `hasEffectiveExtraModels || configurations.count > 1` guard true, so the
/// staged `NexusMigrationPlan` is dropped and SwiftData lightweight *inference*
/// upgrades the on-disk store instead. The single-config staged-plan tests in
/// `NexusMigrationPlanTests` / `NexusSchemaV7MigrationTests` do NOT cover this
/// branch, so this test seeds a real V6-era on-disk store and reopens it
/// through the production split path to prove the additive V6 -> V7 expansion
/// is loss-free without the staged plan.
@MainActor
@Test func splitContainerInfersV6ToV7LightweightExpansionOnDisk() throws {
    let storeURL = temporaryStoreURL(prefix: "nexus-v6-to-v7-split-inference")
    defer { cleanupStores(at: [storeURL, NexusModelContainer.localOnlyStoreURL(for: storeURL)]) }

    // Seed a V6-era on-disk store with pre-existing baseline rows so survival
    // across the inferred lightweight expansion is provable.
    let seededTaskID = try seedV6BaselineStore(at: storeURL, taskTitle: "pre-V7 split task")

    // Reopen through the real production entry. `make(...)` emits the
    // synced + local-only 2-config split, so this drives the
    // `configurations.count > 1` bypass branch in `makeContainer` (NOT the
    // single-config staged-plan branch).
    let container = try NexusModelContainer.make(
        environment: LocalOnlySplitTestEnvironment(),
        fileURL: storeURL
    )
    let context = ModelContext(container)

    // (a) Pre-existing V6 rows survive the inferred expansion (no data loss).
    let tasks = try context.fetch(FetchDescriptor<TaskItem>())
    #expect(tasks.map(\.id).contains(seededTaskID))
    #expect(tasks.first { $0.id == seededTaskID }?.title == "pre-V7 split task")
    #expect(try context.fetch(FetchDescriptor<QuotaLog>()).count == 1)

    // (c) The new V7 tables start empty — no seeder runs during container open
    // (consistent with the no-`.custom`-stage decision; the catalog seed is a
    // composition-root concern, Task 4/14).
    #expect(try context.fetch(FetchDescriptor<ModelManifest>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ModelDownloadEvent>()).isEmpty)

    // (b) Both new V7 entities are usable through the production container:
    // insert + save + fetch round-trips.
    context.insert(
        ModelManifest(
            id: "qwen3.5-4b-instruct-4bit",
            hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
            family: "qwen3.5",
            displayName: "Qwen 3.5 4B",
            sizeGB: 3.2,
            recommendedRAMGB: 16,
            contextLength: 16_384,
            supportsTools: true,
            supportsVision: false,
            supportedLocales: ["en", "pl"],
            purpose: "chat"
        )
    )
    context.insert(
        ModelDownloadEvent(
            modelManifestID: "qwen3.5-4b-instruct-4bit",
            kind: "completed",
            occurredAt: Date(timeIntervalSince1970: 1_778_400_000),
            bytesTransferred: 3_200_000_000,
            durationSeconds: 180.0
        )
    )
    try context.save()

    #expect(try context.fetch(FetchDescriptor<ModelManifest>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<ModelDownloadEvent>()).count == 1)
}

private struct LocalOnlySplitTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"
}

private func modelNames(_ models: [any PersistentModel.Type]) -> [String] {
    models.map { String(describing: $0) }
}

private func entityNames(in schema: Schema?) -> [String] {
    (schema?.entities.map(\.name) ?? []).sorted()
}

private func isNoCloudKitDatabase(_ database: ModelConfiguration.CloudKitDatabase) -> Bool {
    String(reflecting: database).contains("_none: true")
}

private func isPrivateCloudKitDatabase(_ database: ModelConfiguration.CloudKitDatabase) -> Bool {
    let reflected = String(reflecting: database)
    return reflected.contains("_none: false") && reflected.contains("iCloud.com.kacperpietrzyk.Nexus")
}

private func temporaryStoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-local-only-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeStoreFamilyMarker(_ marker: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "\(marker)-primary".write(to: url, atomically: true, encoding: .utf8)
    try "\(marker)-wal".write(to: url.storeSidecarURL(suffix: "-wal"), atomically: true, encoding: .utf8)
    try "\(marker)-shm".write(to: url.storeSidecarURL(suffix: "-shm"), atomically: true, encoding: .utf8)
}

@MainActor
private func makeLegacyMonolithicV6Store(
    at url: URL,
    conflictID: UUID,
    itemID: UUID,
    summary: String
) throws {
    let schema = Schema(versionedSchema: NexusSchemaV6.self)
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        ]
    )
    let context = ModelContext(container)
    let conflict = ConflictLog(
        itemKind: .task,
        itemID: itemID,
        resolution: .setMerge,
        summary: summary
    )
    conflict.id = conflictID
    context.insert(conflict)
    try context.save()
}

/// Seeds a V6-era on-disk store with a `TaskItem` + `QuotaLog` baseline row and
/// returns the seeded task's id so a later production reopen can prove the rows
/// survive the inferred V6 -> V7 lightweight expansion.
@MainActor
private func seedV6BaselineStore(at url: URL, taskTitle: String) throws -> UUID {
    let schema = Schema(versionedSchema: NexusSchemaV6.self)
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ]
    )
    let context = ModelContext(container)
    let task = TaskItem(title: taskTitle)
    context.insert(task)
    context.insert(
        QuotaLog(
            id: UUID(),
            providerRaw: "appleIntelligence",
            day: .now,
            promptTokens: 7,
            completionTokens: 11
        )
    )
    try context.save()
    return task.id
}

private func cleanupStores(at urls: [URL]) {
    for url in urls {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
    }
}

extension URL {
    fileprivate func storeSidecarURL(suffix: String) -> URL {
        URL(fileURLWithPath: path + suffix)
    }
}
