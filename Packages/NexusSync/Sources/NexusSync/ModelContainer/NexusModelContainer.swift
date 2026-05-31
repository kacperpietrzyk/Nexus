import Foundation
import NexusCore
import SQLite3
import SwiftData

/// Abstraction so tests can inject a stub environment without touching ProcessInfo.
public protocol NexusEnvironmentProviding: Sendable {
    var cloudKitEnabled: Bool { get }
    var cloudKitContainerIdentifier: String { get }
}

extension NexusEnvironment: NexusEnvironmentProviding {}

/// Single source of truth for the SwiftData container the apps install via `.modelContainer(...)`.
/// Currently bound to `NexusSchemaV7` (V6 + MLX model catalog entities). CloudKit mirroring is gated by
/// `NexusEnvironment.cloudKitEnabled` — when off, the container is local-only.
public enum NexusModelContainer {
    public static let appGroupIdentifier = "group.com.kacperpietrzyk.Nexus"
    static let syncedConfigurationName = "NexusSynced"
    static let localOnlyConfigurationName = "NexusLocalOnly"

    public enum StoreMigrationResult: Equatable, Sendable {
        case appGroupUnavailable
        case sourceMissing
        case copiedToMissingDestination
        case replacedEmptyDestination
        case skippedEmptySource
        case skippedNonEmptyDestination
    }

    struct StoreFamilyMigrationResult: Equatable, Sendable {
        let main: StoreMigrationResult
        let localOnly: StoreMigrationResult
    }

    /// In-memory container for unit tests. Does NOT touch CloudKit.
    ///
    /// `extraModels` lets composition packages add their own SwiftData entities
    /// without making NexusSync import them. Duplicate entries are accepted and
    /// deduplicated by `NexusSchemaV7`.
    public static func makeInMemory(
        extraModels: [any PersistentModel.Type] = [],
        localOnlyExtraModels: [any PersistentModel.Type] = []
    ) throws -> ModelContainer {
        let configurationPlan = makeConfigurationPlan(
            extraModels: extraModels,
            localOnlyExtraModels: localOnlyExtraModels,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try makeContainer(
            for: configurationPlan.containerSchema,
            hasEffectiveExtraModels: configurationPlan.hasEffectiveExtraModels,
            configurations: configurationPlan.configurations
        )
    }

    /// On-disk container. Use this for app launch.
    /// - Parameters:
    ///   - environment: usually `NexusEnvironment.current`. Injected so tests can flip the flag.
    ///   - fileURL: optional override for the SQLite store URL — defaults to Application Support.
    ///   - groupContainerIdentifier: optional App Group identifier (e.g.
    ///     `group.com.kacperpietrzyk.Nexus`). When provided AND `fileURL` is nil,
    ///     the SQLite store is placed inside the shared App Group container so that
    ///     widget / digest extensions can read the same SwiftData store. Ignored if
    ///     `fileURL` is also supplied (the explicit override wins). Requires the
    ///     App Group entitlement to be active in the Apple Developer Portal at
    ///     runtime; without activation, `containerURL(forSecurityApplicationGroupIdentifier:)`
    ///     returns nil and we fall back to the default Application Support path.
    ///   - extraModels: composition-time models from packages that cannot be imported by
    ///     NexusSync. Duplicate entries are accepted and deduplicated by `NexusSchemaV7`.
    ///   - localOnlyExtraModels: composition-time models that must be present in the
    ///     container but excluded from CloudKit-backed configurations.
    public static func make(
        environment: NexusEnvironmentProviding = NexusEnvironment.current,
        fileURL: URL? = nil,
        groupContainerIdentifier: String? = nil,
        extraModels: [any PersistentModel.Type] = [],
        localOnlyExtraModels: [any PersistentModel.Type] = []
    ) throws -> ModelContainer {
        let url = try resolveStoreURL(
            fileURL: fileURL,
            groupContainerIdentifier: groupContainerIdentifier
        )
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase =
            if environment.cloudKitEnabled {
                .private(environment.cloudKitContainerIdentifier)
            } else {
                .none
            }
        let configurationPlan = makeConfigurationPlan(
            extraModels: extraModels,
            localOnlyExtraModels: localOnlyExtraModels,
            isStoredInMemoryOnly: false,
            storeURL: url,
            cloudKitDatabase: cloudKitDatabase
        )
        try backfillLocalOnlyBaselineRowsIfNeeded(storeURL: url, extraModels: extraModels)
        return try makeContainer(
            for: configurationPlan.containerSchema,
            hasEffectiveExtraModels: configurationPlan.hasEffectiveExtraModels,
            configurations: configurationPlan.configurations
        )
    }

    static func modelPartitions(
        extraModels: [any PersistentModel.Type] = [],
        localOnlyExtraModels: [any PersistentModel.Type] = []
    ) -> ModelPartitions {
        let allModels = NexusSchemaV7.assembledModels(extraModels: extraModels + localOnlyExtraModels)
        let baselineSyncedIdentifiers = Set(
            NexusSchemaV7.models
                .filter { ObjectIdentifier($0) != ObjectIdentifier(ConflictLog.self) }
                .map(ObjectIdentifier.init)
        )
        let effectiveLocalOnlyExtras = localOnlyExtraModels.filter { model in
            !baselineSyncedIdentifiers.contains(ObjectIdentifier(model))
        }
        let localOnlyModels = deduplicatedModels([ConflictLog.self] + effectiveLocalOnlyExtras)
        let localOnlyIdentifiers = Set(localOnlyModels.map(ObjectIdentifier.init))
        let syncedModels = allModels.filter { model in
            !localOnlyIdentifiers.contains(ObjectIdentifier(model))
        }

        return ModelPartitions(
            containerModels: allModels,
            syncedModels: syncedModels,
            localOnlyModels: localOnlyModels,
            hasEffectiveExtraModels: allModels.count > NexusSchemaV7.models.count
        )
    }

    static func makeConfigurationPlan(
        extraModels: [any PersistentModel.Type] = [],
        localOnlyExtraModels: [any PersistentModel.Type] = [],
        isStoredInMemoryOnly: Bool,
        storeURL: URL? = nil,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase
    ) -> ModelConfigurationPlan {
        let partitions = modelPartitions(
            extraModels: extraModels,
            localOnlyExtraModels: localOnlyExtraModels
        )
        let syncedSchema = Schema(partitions.syncedModels, version: NexusSchemaV7.versionIdentifier)
        let localOnlySchema = Schema(partitions.localOnlyModels, version: NexusSchemaV7.versionIdentifier)
        let configurations: [ModelConfiguration]

        if isStoredInMemoryOnly {
            configurations = [
                ModelConfiguration(
                    syncedConfigurationName,
                    schema: syncedSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: cloudKitDatabase
                ),
                ModelConfiguration(
                    localOnlyConfigurationName,
                    schema: localOnlySchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                ),
            ]
        } else {
            guard let storeURL else {
                preconditionFailure("On-disk ModelConfiguration plans require a store URL.")
            }
            configurations = [
                ModelConfiguration(
                    syncedConfigurationName,
                    schema: syncedSchema,
                    url: storeURL,
                    cloudKitDatabase: cloudKitDatabase
                ),
                ModelConfiguration(
                    localOnlyConfigurationName,
                    schema: localOnlySchema,
                    url: localOnlyStoreURL(for: storeURL),
                    cloudKitDatabase: .none
                ),
            ]
        }

        return ModelConfigurationPlan(
            containerSchema: Schema(partitions.containerModels, version: NexusSchemaV7.versionIdentifier),
            configurations: configurations,
            partitions: partitions
        )
    }

    private static func deduplicatedModels(_ models: [any PersistentModel.Type]) -> [any PersistentModel.Type] {
        var seen = Set<ObjectIdentifier>()
        var deduplicated: [any PersistentModel.Type] = []

        for model in models {
            let identifier = ObjectIdentifier(model)
            guard seen.insert(identifier).inserted else { continue }
            deduplicated.append(model)
        }

        return deduplicated
    }

    private static func makeContainer(
        for schema: Schema,
        hasEffectiveExtraModels: Bool,
        configurations: [ModelConfiguration]
    ) throws -> ModelContainer {
        guard hasEffectiveExtraModels || configurations.count > 1 else {
            return try ModelContainer(
                for: schema,
                migrationPlan: NexusMigrationPlan.self,
                configurations: configurations
            )
        }

        // Staged migrations only know the static VersionedSchema chain. Once
        // composition adds models from another package or splits the schema
        // across multiple configurations, SwiftData must open the assembled
        // schema directly and infer the lightweight expansion.
        return try ModelContainer(
            for: schema,
            configurations: configurations
        )
    }
}

extension NexusModelContainer {
    /// Before iOS moves from its app-private store to the App Group store, copy
    /// the existing SQLite files once if the shared destination is still empty.
    /// Extensions already read/write the App Group path; this keeps pre-release
    /// local data visible after enabling that path in the host app.
    @discardableResult
    public static func migrateDefaultStoreToAppGroupIfNeeded(
        groupContainerIdentifier: String = Self.appGroupIdentifier,
        extraModels: [any PersistentModel.Type] = []
    ) throws -> StoreMigrationResult {
        guard let groupURL = groupStoreURL(for: groupContainerIdentifier) else {
            return .appGroupUnavailable
        }
        let migrated = try migrateStoreFamiliesIfNeeded(from: defaultStoreURL(), to: groupURL)
        try backfillLocalOnlyBaselineRowsIfNeeded(storeURL: groupURL, extraModels: extraModels)
        return migrated.main
    }

    @discardableResult
    static func migrateStoreFamiliesIfNeeded(
        from sourceURL: URL, to destinationURL: URL
    ) throws -> StoreFamilyMigrationResult {
        let mainResult = try migrateStoreFilesIfNeeded(from: sourceURL, to: destinationURL)
        let localOnlyResult = try migrateStoreFilesIfNeeded(
            from: localOnlyStoreURL(for: sourceURL),
            to: localOnlyStoreURL(for: destinationURL)
        )
        return StoreFamilyMigrationResult(main: mainResult, localOnly: localOnlyResult)
    }

    @discardableResult
    static func migrateStoreFilesIfNeeded(from sourceURL: URL, to destinationURL: URL) throws -> StoreMigrationResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return .sourceMissing
        }
        let destinationStoreFiles = storeFileURLs(for: destinationURL)
        let destinationExists = destinationStoreFiles.contains(where: { fileManager.fileExists(atPath: $0.path) })

        if destinationExists {
            guard storeContainsUserData(at: sourceURL) else {
                return .skippedEmptySource
            }
            guard !storeContainsUserData(at: destinationURL) else {
                return .skippedNonEmptyDestination
            }
            try replaceStoreFiles(from: sourceURL, to: destinationURL)
            return .replacedEmptyDestination
        }

        try copyStoreFiles(from: sourceURL, to: destinationURL)
        return .copiedToMissingDestination
    }

    private static func copyStoreFiles(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let pairs = zip(storeFileURLs(for: sourceURL), storeFileURLs(for: destinationURL))
        for (source, destination) in pairs where fileManager.fileExists(atPath: source.path) {
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private static func replaceStoreFiles(from sourceURL: URL, to destinationURL: URL) throws {
        let tempURL =
            destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".nexus-store-migration-\(UUID().uuidString).store")
        let tempStoreFiles = storeFileURLs(for: tempURL)
        defer {
            for url in tempStoreFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }

        try copyStoreFiles(from: sourceURL, to: tempURL)

        for url in storeFileURLs(for: destinationURL) where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let pairs = zip(tempStoreFiles, storeFileURLs(for: destinationURL))
        for (temp, destination) in pairs where FileManager.default.fileExists(atPath: temp.path) {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
    }

    /// Picks the on-disk store URL based on priority: explicit `fileURL` >
    /// App Group container (when `groupContainerIdentifier` is set AND the
    /// entitlement is active) > default Application Support path.
    private static func resolveStoreURL(
        fileURL: URL?,
        groupContainerIdentifier: String?
    ) throws -> URL {
        if let fileURL {
            return fileURL
        }
        if let groupURL = groupContainerIdentifier.flatMap(groupStoreURL(for:)) {
            return groupURL
        }
        return try defaultStoreURL()
    }

    static func localOnlyStoreURL(for storeURL: URL) -> URL {
        URL(fileURLWithPath: storeURL.path + "-local")
    }

    private static func defaultStoreURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Nexus", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("nexus.store")
    }

    /// Returns a SQLite store URL inside the shared App Group container, or nil if
    /// the App Group entitlement isn't active (Apple Developer Portal activation is
    /// a manual blocker — extensions rely on this path once activation lands).
    private static func groupStoreURL(for identifier: String) -> URL? {
        guard
            let base = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier)
        else {
            return nil
        }
        let dir = base.appendingPathComponent("Nexus", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir.appendingPathComponent("nexus.store")
    }

    private static func storeFileURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]
    }

    private static func storeContainsUserData(at storeURL: URL) -> Bool {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storeURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return true
        }
        defer { sqlite3_close(database) }

        var foundUserDataTable = false
        for tableName in userDataTableNames where tableExists(tableName, in: database) {
            foundUserDataTable = true
            if tableHasRows(tableName, in: database) {
                return true
            }
        }
        return foundUserDataTable ? false : storeFileSize(at: storeURL) > 0
    }

    private static func backfillLocalOnlyBaselineRowsIfNeeded(
        storeURL: URL,
        extraModels: [any PersistentModel.Type] = []
    ) throws {
        try backfillLegacyConflictLogsIfNeeded(
            from: storeURL,
            to: localOnlyStoreURL(for: storeURL),
            extraModels: extraModels
        )
    }

    static func backfillLegacyConflictLogsIfNeeded(
        from sourceURL: URL,
        to localOnlyURL: URL,
        extraModels: [any PersistentModel.Type] = []
    ) throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path),
            storeTableHasRows("ZCONFLICTLOG", at: sourceURL)
        else {
            return
        }

        // Open the source (synced) store with the SAME assembled schema production uses for it —
        // including composition-time synced entities like Meeting (passed via extraModels). The
        // old `Schema(versionedSchema: NexusSchemaV7.self)` omitted Meeting, which the synced
        // store physically contains (ZMEETING), so SwiftData saw an entity "removed" on open and
        // could throw or migrate destructively. With extraModels == [] this is identical to the
        // previous schema, so callers that don't supply them are unchanged.
        let legacySchema = NexusSchemaV7.schema(extraModels: extraModels)
        let legacyContainer = try ModelContainer(
            for: legacySchema,
            migrationPlan: NexusMigrationPlan.self,
            configurations: [
                ModelConfiguration(
                    schema: legacySchema,
                    url: sourceURL,
                    cloudKitDatabase: .none
                )
            ]
        )
        let legacyContext = ModelContext(legacyContainer)
        let legacyLogs = try legacyContext.fetch(FetchDescriptor<ConflictLog>())
        guard !legacyLogs.isEmpty else { return }

        let localOnlySchema = Schema([ConflictLog.self], version: NexusSchemaV7.versionIdentifier)
        let localOnlyContainer = try ModelContainer(
            for: localOnlySchema,
            configurations: [
                ModelConfiguration(
                    schema: localOnlySchema,
                    url: localOnlyURL,
                    cloudKitDatabase: .none
                )
            ]
        )
        let localOnlyContext = ModelContext(localOnlyContainer)
        let existingIDs = Set(try localOnlyContext.fetch(FetchDescriptor<ConflictLog>()).map(\.id))
        var inserted = false

        for log in legacyLogs where !existingIDs.contains(log.id) {
            let copy = ConflictLog(
                itemKind: log.itemKind,
                itemID: log.itemID,
                resolution: log.resolution,
                summary: log.summary,
                timestamp: log.timestamp
            )
            copy.id = log.id
            localOnlyContext.insert(copy)
            inserted = true
        }

        if inserted {
            try localOnlyContext.save()
        }
    }

    private static var userDataTableNames: [String] {
        [
            "ZLINK",
            "ZDEBUGITEM",
            "ZCONFLICTLOG",
            "ZQUOTALOG",
            "ZTASKITEM",
            "ZPROJECT",
            "ZSECTION",
            "ZSAVEDFILTER",
            "ZMEETING",
            "ZMEETINGAUDIOSTORAGE",
        ]
    }

    private static func tableHasRows(_ tableName: String, in database: OpaquePointer) -> Bool {
        let sql = #"SELECT 1 FROM "\#(tableName.replacingOccurrences(of: "\"", with: "\"\""))" LIMIT 1"#
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func tableExists(_ tableName: String, in database: OpaquePointer) -> Bool {
        let escaped = tableName.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(escaped)' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func storeTableHasRows(_ tableName: String, at storeURL: URL) -> Bool {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storeURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }
        defer { sqlite3_close(database) }

        guard tableExists(tableName, in: database) else {
            return false
        }
        return tableHasRows(tableName, in: database)
    }

    private static func storeFileSize(at storeURL: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: storeURL.path)
        return attributes?[.size] as? Int64 ?? 0
    }
}

struct ModelPartitions {
    let containerModels: [any PersistentModel.Type]
    let syncedModels: [any PersistentModel.Type]
    let localOnlyModels: [any PersistentModel.Type]
    let hasEffectiveExtraModels: Bool
}

struct ModelConfigurationPlan {
    let containerSchema: Schema
    let configurations: [ModelConfiguration]
    let partitions: ModelPartitions

    var hasEffectiveExtraModels: Bool {
        partitions.hasEffectiveExtraModels
    }
}
