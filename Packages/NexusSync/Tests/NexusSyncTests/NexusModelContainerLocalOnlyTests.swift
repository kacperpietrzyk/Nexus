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

/// The legacy `ConflictLog` backfill is a one-time migration: the ZCONFLICTLOG
/// table physically survives the split migration, so the cheap row probe stays
/// true forever and (pre-fix) reopened the expensive synced container on every
/// launch. A completion marker must make it run at most once per source store.
/// Appending a fresh row after completion is artificial (production never writes
/// ConflictLog to the synced store anymore) — it exists purely to prove the
/// marker short-circuits the second pass.
@Test func legacyConflictLogBackfillRunsOnlyOncePerSource() throws {
    let storeURL = temporaryStoreURL(prefix: "nexus-backfill-once")
    let localOnlyURL = NexusModelContainer.localOnlyStoreURL(for: storeURL)
    defer { cleanupStores(at: [storeURL, localOnlyURL]) }

    let suiteName = "nexus-backfill-once-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let firstID = UUID()
    try makeLegacyMonolithicV6Store(at: storeURL, conflictID: firstID, itemID: UUID(), summary: "first")

    // First pass copies the legacy row and records completion.
    try NexusModelContainer.backfillLegacyConflictLogsIfNeeded(
        from: storeURL,
        to: localOnlyURL,
        defaults: defaults
    )
    let key = NexusModelContainer.legacyConflictLogBackfillCompletionKey(for: storeURL)
    #expect(defaults.bool(forKey: key))
    #expect(try copiedConflictLogIDs(at: localOnlyURL).contains(firstID))

    // A new legacy row appears in the source after completion...
    let secondID = UUID()
    try appendConflictLog(to: storeURL, conflictID: secondID, summary: "second")

    // ...but the marker short-circuits the second pass, so it is NOT copied
    // (the expensive synced container is never reopened).
    try NexusModelContainer.backfillLegacyConflictLogsIfNeeded(
        from: storeURL,
        to: localOnlyURL,
        defaults: defaults
    )
    let finalIDs = try copiedConflictLogIDs(at: localOnlyURL)
    #expect(finalIDs.contains(firstID))
    #expect(
        !finalIDs.contains(secondID),
        "completion marker must prevent reopening the synced store after the one-time drain"
    )
}

private func copiedConflictLogIDs(at localOnlyURL: URL) throws -> [UUID] {
    let schema = Schema([ConflictLog.self], version: NexusSchemaV7.versionIdentifier)
    let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, url: localOnlyURL, cloudKitDatabase: .none)]
    )
    return try ModelContext(container).fetch(FetchDescriptor<ConflictLog>()).map(\.id)
}

private func appendConflictLog(to sourceURL: URL, conflictID: UUID, summary: String) throws {
    // The backfill's reopen migrated the on-disk store to V7, so append on V7.
    let schema = NexusSchemaV7.schema()
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [ModelConfiguration(schema: schema, url: sourceURL, cloudKitDatabase: .none)]
    )
    let context = ModelContext(container)
    let conflict = ConflictLog(itemKind: .task, itemID: UUID(), resolution: .setMerge, summary: summary)
    conflict.id = conflictID
    context.insert(conflict)
    try context.save()
}

/// Regression for the backfill reopening the synced store with a schema that OMITTED
/// composition-time synced entities (Meeting / ZMEETING). The store physically contains those
/// tables, so a Meeting-less reopen made SwiftData see an entity "removed" and risked a throw or
/// destructive migration on the launch path. `StubSyncedExtra` stands in for Meeting (NexusSync
/// cannot import NexusMeetings). The existing backfill test seeds NO extra entity, so it never
/// exercised this path.
@MainActor
@Test func backfillReopensSourceWithExtraSyncedEntityPresent() throws {
    let storeURL = temporaryStoreURL(prefix: "nexus-backfill-extra-synced")
    let localOnlyURL = NexusModelContainer.localOnlyStoreURL(for: storeURL)
    defer { cleanupStores(at: [storeURL, localOnlyURL]) }

    let conflictID = UUID()
    try seedSyncedStoreWithExtraEntity(at: storeURL, conflictID: conflictID)

    // Must open the source with a schema INCLUDING the extra entity, copy the ConflictLog into
    // the local-only store, and neither crash nor drop the extra entity's rows.
    try NexusModelContainer.backfillLegacyConflictLogsIfNeeded(
        from: storeURL,
        to: localOnlyURL,
        extraModels: [StubSyncedExtra.self]
    )

    let localOnlySchema = Schema([ConflictLog.self], version: NexusSchemaV7.versionIdentifier)
    let localOnlyContainer = try ModelContainer(
        for: localOnlySchema,
        configurations: [
            ModelConfiguration(schema: localOnlySchema, url: localOnlyURL, cloudKitDatabase: .none)
        ]
    )
    let copied = try ModelContext(localOnlyContainer).fetch(FetchDescriptor<ConflictLog>())
    #expect(copied.map(\.id).contains(conflictID))

    // The extra entity's rows survive in the source (no destructive migration on reopen).
    let sourceSchema = NexusSchemaV7.schema(extraModels: [StubSyncedExtra.self])
    let sourceContainer = try ModelContainer(
        for: sourceSchema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: sourceSchema, url: storeURL, cloudKitDatabase: .none)
        ]
    )
    let survivors = try ModelContext(sourceContainer).fetch(FetchDescriptor<StubSyncedExtra>())
    #expect(survivors.count == 1)
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

/// Stand-in for a composition-time synced entity (e.g. `Meeting`) that NexusSync cannot import.
@Model
final class StubSyncedExtra {
    var stubID: UUID
    var label: String
    init(stubID: UUID = UUID(), label: String) {
        self.stubID = stubID
        self.label = label
    }
}

/// Seeds a synced store that holds BOTH a legacy `ConflictLog` row and a composition-time synced
/// extra entity (`StubSyncedExtra`), mirroring a real synced store with `Meeting` present.
@MainActor
private func seedSyncedStoreWithExtraEntity(at url: URL, conflictID: UUID) throws {
    let schema = NexusSchemaV7.schema(extraModels: [StubSyncedExtra.self])
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ]
    )
    let context = ModelContext(container)
    let conflict = ConflictLog(
        itemKind: .task,
        itemID: UUID(),
        resolution: .setMerge,
        summary: "extra-present conflict"
    )
    conflict.id = conflictID
    context.insert(conflict)
    context.insert(StubSyncedExtra(label: "keep me"))
    try context.save()
}

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
