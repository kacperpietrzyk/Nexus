import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@MainActor
@Test func nexusModelContainer_inMemory_returnsUsableContainer() throws {
    let container = try NexusModelContainer.makeInMemory()
    let context = ModelContext(container)
    let item = DebugItem(title: "Hello sync")
    context.insert(item)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<DebugItem>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.title == "Hello sync")
}

@MainActor
@Test func nexusModelContainer_makeOnDisk_disabledCloudKit_isLocalOnly() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let env = StubEnv(cloudKitEnabled: false)
    let container = try NexusModelContainer.make(environment: env, fileURL: url)

    // Verify by exercising real persistence — insert an item, save, fetch it back.
    // CloudKit-disabled mode must still give a working local store.
    let context = ModelContext(container)
    let item = DebugItem(title: "Local-only persistence check")
    context.insert(item)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<DebugItem>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.title == "Local-only persistence check")
}

@MainActor
@Test func nexusModelContainer_includesAllSchemaModels() throws {
    let container = try NexusModelContainer.makeInMemory()
    let context = ModelContext(container)
    let from = UUID()
    let to = UUID()
    let link = Link(from: (.debug, from), to: (.debug, to), linkKind: .mentions)
    context.insert(link)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Link>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.fromID == from)
}

@MainActor
@Test func makeInMemoryUsesV6() throws {
    let container = try NexusModelContainer.makeInMemory()
    let context = ModelContext(container)
    context.insert(
        QuotaLog(
            id: UUID(),
            providerRaw: "chatGPTOAuth",
            day: .now,
            promptTokens: 1,
            completionTokens: 1
        ))
    try context.save()
    let fetched = try context.fetch(FetchDescriptor<QuotaLog>())
    #expect(fetched.count == 1)
}

@MainActor
@Test func makeInMemoryPersistsTaskItem() throws {
    let container = try NexusModelContainer.makeInMemory()
    let context = ModelContext(container)
    context.insert(TaskItem(title: "container smoke"))
    try context.save()
    let fetched = try context.fetch(FetchDescriptor<TaskItem>())
    #expect(fetched.count == 1)
}

@Test func nexusSchemaV6AssembledModelsDeduplicateBaselineExtras() {
    let modelTypes = NexusSchemaV6.assembledModels(extraModels: [
        TaskItem.self,
        Link.self,
        TaskItem.self,
    ]).map { String(describing: $0) }

    #expect(modelTypes.filter { $0 == "TaskItem" }.count == 1)
    #expect(modelTypes.filter { $0 == "Link" }.count == 1)
    #expect(
        modelTypes.prefix(8) == [
            "Link",
            "DebugItem",
            "ConflictLog",
            "QuotaLog",
            "TaskItem",
            "Project",
            "Section",
            "SavedFilter",
        ])
}

@MainActor
@Test func makeInMemoryDeduplicatesBaselineExtraModels() throws {
    let container = try NexusModelContainer.makeInMemory(extraModels: [
        TaskItem.self,
        TaskItem.self,
    ])
    let context = ModelContext(container)

    context.insert(TaskItem(title: "deduped baseline extra"))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<TaskItem>())
    #expect(fetched.map(\.title).contains("deduped baseline extra"))
}

@Test func migrateStoreFilesIfNeededCopiesPrimaryAndSidecars() throws {
    let dir = try tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.store")
    let destination = dir.appendingPathComponent("nested/destination.store")
    try "primary".write(to: source, atomically: true, encoding: .utf8)
    try "wal".write(to: source.storeSidecarURL(suffix: "-wal"), atomically: true, encoding: .utf8)
    try "shm".write(to: source.storeSidecarURL(suffix: "-shm"), atomically: true, encoding: .utf8)

    let migrated = try NexusModelContainer.migrateStoreFilesIfNeeded(from: source, to: destination)

    #expect(migrated == .copiedToMissingDestination)
    #expect(try String(contentsOf: destination, encoding: .utf8) == "primary")
    #expect(try String(contentsOf: destination.storeSidecarURL(suffix: "-wal"), encoding: .utf8) == "wal")
    #expect(try String(contentsOf: destination.storeSidecarURL(suffix: "-shm"), encoding: .utf8) == "shm")
}

@Test func migrateStoreFilesIfNeededDoesNotOverwriteExistingDestination() throws {
    let dir = try tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.store")
    let destination = dir.appendingPathComponent("destination.store")
    try "source".write(to: source, atomically: true, encoding: .utf8)
    try "destination".write(to: destination, atomically: true, encoding: .utf8)

    let migrated = try NexusModelContainer.migrateStoreFilesIfNeeded(from: source, to: destination)

    #expect(migrated == .skippedNonEmptyDestination)
    #expect(try String(contentsOf: destination, encoding: .utf8) == "destination")
}

@Test func migrateStoreFilesIfNeededDoesNotOverwriteExistingDestinationSidecars() throws {
    let dir = try tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.store")
    let destination = dir.appendingPathComponent("destination.store")
    try "source".write(to: source, atomically: true, encoding: .utf8)
    try "destination-wal".write(to: destination.storeSidecarURL(suffix: "-wal"), atomically: true, encoding: .utf8)

    let migrated = try NexusModelContainer.migrateStoreFilesIfNeeded(from: source, to: destination)

    #expect(migrated == .skippedNonEmptyDestination)
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(try String(contentsOf: destination.storeSidecarURL(suffix: "-wal"), encoding: .utf8) == "destination-wal")
}

@MainActor
@Test func migrateStoreFilesIfNeededReplacesExistingEmptySwiftDataDestination() throws {
    let dir = try tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.store")
    let destination = dir.appendingPathComponent("destination.store")
    try makeSwiftDataStore(at: source, taskTitle: "Legacy app-private task")
    try makeSwiftDataStore(at: destination)

    let migrated = try NexusModelContainer.migrateStoreFilesIfNeeded(from: source, to: destination)

    #expect(migrated == .replacedEmptyDestination)
    #expect(try taskTitles(in: destination) == ["Legacy app-private task"])
}

@MainActor
@Test func migrateStoreFilesIfNeededSkipsExistingNonEmptySwiftDataDestination() throws {
    let dir = try tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.store")
    let destination = dir.appendingPathComponent("destination.store")
    try makeSwiftDataStore(at: source, taskTitle: "Legacy app-private task")
    try makeSwiftDataStore(at: destination, taskTitle: "App Group task")

    let migrated = try NexusModelContainer.migrateStoreFilesIfNeeded(from: source, to: destination)

    #expect(migrated == .skippedNonEmptyDestination)
    #expect(try taskTitles(in: destination) == ["App Group task"])
}

private struct StubEnv: NexusEnvironmentProviding {
    let cloudKitEnabled: Bool
    var cloudKitContainerIdentifier: String { NexusEnvironment.containerIdentifier }
}

private func tempURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-test-\(UUID().uuidString).store")
}

private func tempDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

extension URL {
    fileprivate func storeSidecarURL(suffix: String) -> URL {
        URL(fileURLWithPath: path + suffix)
    }
}

@MainActor
private func makeSwiftDataStore(at url: URL, taskTitle: String? = nil) throws {
    let container = try NexusModelContainer.make(environment: StubEnv(cloudKitEnabled: false), fileURL: url)
    if let taskTitle {
        let context = ModelContext(container)
        context.insert(TaskItem(title: taskTitle))
        try context.save()
    }
}

@MainActor
private func taskTitles(in url: URL) throws -> [String] {
    let container = try NexusModelContainer.make(environment: StubEnv(cloudKitEnabled: false), fileURL: url)
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<TaskItem>())
        .map(\.title)
}
