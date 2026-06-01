import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent
@testable import NexusSync

// The PRODUCTION list the apps must hand to `NexusModelContainer`. Guarding it
// here is the regression seal: the original defect was the apps registering NONE
// of these, so the container had no agent tables and every turn silently failed
// to persist. All six are LOCAL-ONLY (see `AgentComposition.localOnlyExtraModels`).
private let agentPersistentModels = AgentComposition.localOnlyExtraModels

@Test func agentLocalOnlyExtraModelsListsEveryAgentEntity() {
    let names = Set(AgentComposition.localOnlyExtraModels.map { String(describing: $0) })
    #expect(
        names == [
            "AgentThread",
            "AgentMessage",
            "AgentMemoryEntry",
            "AgentAuditLog",
            "AgentSchedule",
            "ItemEmbedding",
        ]
    )
}

@Test func v6AssembledModelsIncludeAgentEntities() {
    let modelTypes = NexusSchemaV6.assembledModels(extraModels: agentPersistentModels)
        .map { String(describing: $0) }

    #expect(modelTypes.contains("AgentThread"))
    #expect(modelTypes.contains("AgentMessage"))
    #expect(modelTypes.contains("AgentMemoryEntry"))
    #expect(modelTypes.contains("AgentAuditLog"))
    #expect(modelTypes.contains("AgentSchedule"))
    #expect(modelTypes.contains("ItemEmbedding"))
}

@Test func v6AssembledModelsDeduplicateAgentExtras() {
    let modelTypes = NexusSchemaV6.assembledModels(extraModels: [
        AgentThread.self,
        AgentMessage.self,
        AgentThread.self,
        AgentMessage.self,
    ]).map { String(describing: $0) }

    #expect(modelTypes.filter { $0 == "AgentThread" }.count == 1)
    #expect(modelTypes.filter { $0 == "AgentMessage" }.count == 1)
    #expect(modelTypes.suffix(2) == ["AgentThread", "AgentMessage"])
}

// Production places ALL agent entities in the LOCAL-ONLY (non-CloudKit)
// partition — never the synced one — keeping the CloudKit/synced configuration
// byte-identical. These assert that placement WITHOUT instantiating a
// container (a second on-disk SwiftData container in the same test process
// trips CoreData's global entity→store mapping).
@Test func v6AgentModelsAreAllLocalOnlyNeverSynced() {
    let partitions = NexusModelContainer.modelPartitions(
        localOnlyExtraModels: agentPersistentModels
    )
    let syncedModels = modelNames(partitions.syncedModels)
    let localOnlyModels = modelNames(partitions.localOnlyModels)

    for agentModel in agentPersistentModels.map({ String(describing: $0) }) {
        #expect(localOnlyModels.contains(agentModel))
        #expect(!syncedModels.contains(agentModel))
    }
    // Baseline synced entities are untouched by the agent registration.
    #expect(syncedModels.contains("TaskItem"))
    #expect(syncedModels.contains("Project"))
}

@Test func v6AgentCloudConfigurationPlanKeepsEveryAgentEntityLocalOnly() throws {
    let storeURL = tempStoreURL(prefix: "nexus-agent-local-only-config")
    let plan = NexusModelContainer.makeConfigurationPlan(
        localOnlyExtraModels: agentPersistentModels,
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
    let syncedEntities = entityNames(in: syncedConfiguration.schema)
    let localOnlyEntities = entityNames(in: localOnlyConfiguration.schema)

    for agentModel in agentPersistentModels.map({ String(describing: $0) }) {
        #expect(localOnlyEntities.contains(agentModel))
        #expect(!syncedEntities.contains(agentModel))
    }
    #expect(isNoCloudKitDatabase(localOnlyConfiguration.cloudKitDatabase))
}

// The container-instantiating persistence checks below register the agent
// models via `extraModels` (the synced/primary config). This is deliberate and
// matches `AgentTestSupport`'s single-config registration: the same `@Model`
// class placed in DIFFERENT configurations across containers in one test
// process trips CoreData's global entity→store mapping ("Can't assign an
// object to a store that does not contain the object's entity"). Placement in
// the LOCAL-ONLY partition is verified above without instantiating a container;
// here we only assert the entities persist once registered.
@Test func v6AssembledInMemoryContainerPersistsAgentEntity() throws {
    let container = try NexusModelContainer.makeInMemory(extraModels: agentPersistentModels)
    let context = ModelContext(container)

    try insertAndVerifyAllAgentEntities(in: context)
}

@Test func v6AssembledOnDiskContainerPersistsAgentEntity() throws {
    let storeURL = tempStoreURL(prefix: "nexus-agent-v6")
    defer { cleanupStore(at: storeURL) }

    let container = try NexusModelContainer.make(
        environment: AgentSchemaTestEnvironment(),
        fileURL: storeURL,
        extraModels: agentPersistentModels
    )
    let context = ModelContext(container)

    try insertAndVerifyAllAgentEntities(in: context)
}

@Test func baseV6StoreReopensWithAssembledAgentModels() throws {
    let storeURL = tempStoreURL(prefix: "nexus-base-to-agent-v6")
    defer { cleanupStore(at: storeURL) }
    let taskID = UUID()

    do {
        let container = try NexusModelContainer.make(
            environment: AgentSchemaTestEnvironment(),
            fileURL: storeURL
        )
        let context = ModelContext(container)
        context.insert(TaskItem(id: taskID, title: "Base V6 task"))
        try context.save()
    }

    let container = try NexusModelContainer.make(
        environment: AgentSchemaTestEnvironment(),
        fileURL: storeURL,
        extraModels: agentPersistentModels
    )
    let context = ModelContext(container)
    let storedTasks = try context.fetch(FetchDescriptor<TaskItem>())

    #expect(storedTasks.map(\.id).contains(taskID))
    try insertAndVerifyAllAgentEntities(in: context)
}

private func insertAndVerifyAllAgentEntities(in context: ModelContext) throws {
    let thread = AgentThread(title: "Agent smoke")
    let message = AgentMessage(
        threadID: thread.id,
        role: .user,
        content: "hello"
    )
    let memory = AgentMemoryEntry(
        key: "preference",
        content: "prefers morning briefs"
    )
    let auditLog = AgentAuditLog(
        toolName: "agent.test",
        inputJSON: Data(#"{"input":true}"#.utf8),
        outputJSON: Data(#"{"ok":true}"#.utf8),
        affectedItemIDs: [thread.id]
    )
    let schedule = AgentSchedule(
        name: "Morning brief",
        cronExpression: "0 8 * * *",
        prompt: "Summarize today"
    )
    let embedding = ItemEmbedding(
        itemID: UUID(),
        kind: "task",
        vector: Data([0, 1, 2, 3]),
        textHash: "hash"
    )

    context.insert(thread)
    context.insert(message)
    context.insert(memory)
    context.insert(auditLog)
    context.insert(schedule)
    context.insert(embedding)
    try context.save()

    let storedThreads = try context.fetch(FetchDescriptor<AgentThread>())
    let storedMessages = try context.fetch(FetchDescriptor<AgentMessage>())
    let storedMemories = try context.fetch(FetchDescriptor<AgentMemoryEntry>())
    let storedAuditLogs = try context.fetch(FetchDescriptor<AgentAuditLog>())
    let storedSchedules = try context.fetch(FetchDescriptor<AgentSchedule>())
    let storedEmbeddings = try context.fetch(FetchDescriptor<ItemEmbedding>())

    #expect(storedThreads.map(\.id).contains(thread.id))
    #expect(storedMessages.map(\.id).contains(message.id))
    #expect(storedMemories.map(\.id).contains(memory.id))
    #expect(storedAuditLogs.map(\.id).contains(auditLog.id))
    #expect(storedSchedules.map(\.id).contains(schedule.id))
    #expect(storedEmbeddings.map(\.id).contains(embedding.id))
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

private struct AgentSchemaTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"
}

private func tempStoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupStore(at url: URL) {
    let fileManager = FileManager.default
    for storeURL in [url, URL(fileURLWithPath: url.path + "-local")] {
        try? fileManager.removeItem(at: storeURL)
        try? fileManager.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
        try? fileManager.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
    }
}
