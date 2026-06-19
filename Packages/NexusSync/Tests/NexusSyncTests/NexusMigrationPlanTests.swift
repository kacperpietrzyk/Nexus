import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite("NexusMigrationPlan")
struct NexusMigrationPlanTests {

    @Test("plan declares V1 through V17 schemas in order")
    func schemaOrder() {
        let names = NexusMigrationPlan.schemas.map { String(describing: $0) }
        #expect(
            names == [
                "NexusSchemaV1",
                "NexusSchemaV2",
                "NexusSchemaV3",
                "NexusSchemaV4",
                "NexusSchemaV5",
                "NexusSchemaV6",
                "NexusSchemaV7",
                "NexusSchemaV8",
                "NexusSchemaV9",
                "NexusSchemaV10",
                "NexusSchemaV11",
                "NexusSchemaV12",
                "NexusSchemaV13",
                "NexusSchemaV14",
                "NexusSchemaV15",
                "NexusSchemaV16",
                "NexusSchemaV17",
            ])
    }

    @Test("plan has sixteen lightweight stages")
    func stages() {
        #expect(NexusMigrationPlan.stages.count == 16)
        // MigrationStage doesn't expose `.kind` publicly, but we can encode-check via debug repr.
        let descriptions = NexusMigrationPlan.stages.map { String(describing: $0) }
        #expect(descriptions.allSatisfy { $0.contains("lightweight") })
    }

    @Test func migrationPlanEndsAtV17() {
        #expect(NexusMigrationPlan.schemas.last?.versionIdentifier == Schema.Version(17, 0, 0))
        #expect(NexusMigrationPlan.stages.count == NexusMigrationPlan.schemas.count - 1)
    }

    @Test func planRegistersV17AsLightweightTail() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV17.self })
        #expect(NexusMigrationPlan.stages.count == NexusMigrationPlan.schemas.count - 1)
    }

    /// Invariant guard, not a behavioural test. The production container is a
    /// split (synced + local-only) configuration, and `makeContainer` drops
    /// `NexusMigrationPlan` on that path — it relies on SwiftData lightweight
    /// *inference* instead (see `makeContainer` and
    /// `splitContainerInfersV6ToV7LightweightExpansionOnDisk`). That is correct
    /// only while every stage is `.lightweight`. The moment a `.custom` stage is
    /// added, it will silently NOT run for real users, because the plan never
    /// reaches the split container — so this fails loudly to force the author to
    /// also wire the plan into `makeContainer`'s split path and verify it with a
    /// real on-disk migration before shipping.
    ///
    /// NOTE (V8 -> V9, Notes content layer): the `TaskItem.body` -> `Note` data
    /// move is intentionally NOT a `.custom` stage. The V8 -> V9 *schema* delta is
    /// lightweight-additive (Note table + two `UUID?` ref fields), and the data
    /// move runs as plain, idempotent, marker-gated code over the already-open
    /// container in `NexusModelContainer.migrateTaskBodiesToNotesIfNeeded` — proven
    /// end-to-end by `SchemaV9MigrationTests.splitContainerMigratesTaskBodiesToNotesOnDisk`.
    /// A `.custom` stage was infeasible: it could not run on the split inference
    /// path, and a plan-driven pre-pass throws "unknown coordinator model version"
    /// on any store carrying composition extras (Meeting, never in the plan's
    /// schemas due to the package cycle). So this guard is preserved as-is.
    @Test("every stage is lightweight — custom stages would not run in the production split container")
    func everyStageIsLightweightOrTheSplitContainerMustBeRewired() {
        let nonLightweight = NexusMigrationPlan.stages
            .map { String(describing: $0) }
            .filter { !$0.contains("lightweight") }
        #expect(
            nonLightweight.isEmpty,
            """
            A non-lightweight migration stage was added to NexusMigrationPlan, but the production \
            split container (synced + local-only) drops the plan and infers lightweight migrations \
            only. This custom stage will never execute for real users and can silently lose data. \
            Wire NexusMigrationPlan into makeContainer's split path and prove the migration with an \
            on-disk fixture before removing this guard. Offending stage(s): \(nonLightweight)
            """
        )
    }

    @Test("opens fresh in-memory container on V7 schema")
    func opensFreshContainer() throws {
        // Fresh-V7: no old store on disk, V7 schema cold open.
        let schema = Schema(versionedSchema: NexusSchemaV7.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NexusMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        // Insert one of each V2 model to prove migration plan didn't break the schema.
        context.insert(
            Link(
                from: (.note, UUID()),
                to: (.note, UUID()),
                linkKind: .mentions
            ))
        context.insert(
            QuotaLog(
                id: UUID(),
                providerRaw: "appleIntelligence",
                day: .now,
                promptTokens: 1,
                completionTokens: 1
            ))
        context.insert(TaskItem(title: "post-migration smoke"))
        context.insert(Project(name: "Projects smoke"))
        context.insert(Section(projectID: UUID(), name: "Section smoke"))
        context.insert(try SavedFilter(name: "Saved filter smoke", definition: .unsorted))
        try context.save()
    }

    @MainActor
    @Test("V5 store migrates to V6 with additive task fields and new entities")
    func v5ToV6IsLightweightAndAdditive() throws {
        let url = tempStoreURL(prefix: "nexus-v5-to-v6")
        defer { cleanupStore(at: url) }

        try seedV5Store(at: url)

        let schema = Schema(versionedSchema: NexusSchemaV6.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NexusMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(fetched.count == 1)
        let task = try #require(fetched.first)
        #expect(task.id == V5TaskFixture.id)
        #expect(task.kind == .task)
        #expect(task.title == V5TaskFixture.title)
        #expect(task.body == V5TaskFixture.body)
        #expect(task.createdAt == V5TaskFixture.createdAt)
        #expect(task.updatedAt == V5TaskFixture.updatedAt)
        #expect(task.deletedAt == V5TaskFixture.deletedAt)
        #expect(task.dueAt == V5TaskFixture.dueAt)
        #expect(task.startAt == V5TaskFixture.startAt)
        #expect(task.endAt == V5TaskFixture.endAt)
        #expect(task.snoozedUntil == V5TaskFixture.snoozedUntil)
        #expect(task.status == .snoozed)
        #expect(task.statusRaw == TaskStatus.snoozed.rawValue)
        #expect(task.priority == .high)
        #expect(task.priorityRaw == TaskPriority.high.rawValue)
        #expect(task.tags == V5TaskFixture.tags)
        #expect(task.recurrenceRule == V5TaskFixture.recurrenceRule)
        #expect(task.recurrenceParentId == V5TaskFixture.recurrenceParentId)
        #expect(task.lastCompletedAt == V5TaskFixture.lastCompletedAt)
        #expect(task.orderIndex == V5TaskFixture.orderIndex)
        #expect(task.pinnedAsFocus == true)
        #expect(task.externalSourceID == V5TaskFixture.externalSourceID)
        #expect(task.externalSourceMetadata == V5TaskFixture.externalSourceMetadata)
        #expect(task.parentTaskID == nil)
        #expect(task.deadlineAt == nil)
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)

        let project = Project(name: "Test")
        context.insert(project)
        let section = Section(projectID: project.id, name: "Sec A")
        context.insert(section)
        let filter = try SavedFilter(name: "Inbox", definition: .unsorted)
        context.insert(filter)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Section>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SavedFilter>()).count == 1)
    }

    @MainActor
    @Test("V6 store migrates to V7 with additive model catalog entities")
    func v6ToV7IsLightweightAndAdditive() throws {
        let url = tempStoreURL(prefix: "nexus-v6-to-v7")
        defer { cleanupStore(at: url) }

        // Seed a V6 store with a baseline TaskItem.
        let v6Schema = Schema(versionedSchema: NexusSchemaV6.self)
        let v6Config = ModelConfiguration(schema: v6Schema, url: url, cloudKitDatabase: .none)
        let v6Container = try ModelContainer(
            for: v6Schema,
            migrationPlan: NexusMigrationPlan.self,
            configurations: [v6Config]
        )
        let v6Context = ModelContext(v6Container)
        v6Context.insert(TaskItem(title: "pre-V7 task"))
        try v6Context.save()

        // Reopen on V7: lightweight additive migration, existing rows survive.
        let v7Schema = Schema(versionedSchema: NexusSchemaV7.self)
        let v7Config = ModelConfiguration(schema: v7Schema, url: url, cloudKitDatabase: .none)
        let v7Container = try ModelContainer(
            for: v7Schema,
            migrationPlan: NexusMigrationPlan.self,
            configurations: [v7Config]
        )
        let v7Context = ModelContext(v7Container)
        #expect(try v7Context.fetch(FetchDescriptor<TaskItem>()).count == 1)
        #expect(try v7Context.fetch(FetchDescriptor<ModelManifest>()).isEmpty)
        #expect(try v7Context.fetch(FetchDescriptor<ModelDownloadEvent>()).isEmpty)

        v7Context.insert(
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
        v7Context.insert(
            ModelDownloadEvent(
                modelManifestID: "qwen3.5-4b-instruct-4bit",
                kind: "completed",
                occurredAt: Date(timeIntervalSince1970: 1_778_300_000)
            )
        )
        try v7Context.save()

        #expect(try v7Context.fetch(FetchDescriptor<ModelManifest>()).count == 1)
        #expect(try v7Context.fetch(FetchDescriptor<ModelDownloadEvent>()).count == 1)
    }
}

@MainActor
private func seedV5Store(at url: URL) throws {
    let schema = Schema(versionedSchema: NexusSchemaV5.self)
    let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [config]
    )
    let context = ModelContext(container)
    let task = NexusSchemaV5.TaskItem(
        id: V5TaskFixture.id,
        title: V5TaskFixture.title,
        body: V5TaskFixture.body,
        dueAt: V5TaskFixture.dueAt,
        startAt: V5TaskFixture.startAt,
        endAt: V5TaskFixture.endAt,
        priority: .high,
        status: .snoozed,
        tags: V5TaskFixture.tags,
        recurrenceRule: V5TaskFixture.recurrenceRule,
        recurrenceParentId: V5TaskFixture.recurrenceParentId,
        orderIndex: V5TaskFixture.orderIndex,
        pinnedAsFocus: true
    )
    task.createdAt = V5TaskFixture.createdAt
    task.updatedAt = V5TaskFixture.updatedAt
    task.deletedAt = V5TaskFixture.deletedAt
    task.snoozedUntil = V5TaskFixture.snoozedUntil
    task.lastCompletedAt = V5TaskFixture.lastCompletedAt
    task.externalSourceID = V5TaskFixture.externalSourceID
    task.externalSourceMetadata = V5TaskFixture.externalSourceMetadata
    context.insert(task)
    try context.save()
}

private enum V5TaskFixture {
    static let id = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    static let title = "Pre-V6 task"
    static let body = "Body text survives migration"
    static let createdAt = Date(timeIntervalSince1970: 1_778_100_000)
    static let updatedAt = Date(timeIntervalSince1970: 1_778_103_600)
    static let deletedAt = Date(timeIntervalSince1970: 1_778_190_000)
    static let dueAt = Date(timeIntervalSince1970: 1_778_200_000)
    static let startAt = Date(timeIntervalSince1970: 1_778_196_400)
    static let endAt = Date(timeIntervalSince1970: 1_778_203_600)
    static let snoozedUntil = Date(timeIntervalSince1970: 1_778_150_000)
    static let tags = ["phase-1i", "migration"]
    static let recurrenceRule = "FREQ=WEEKLY;BYDAY=MO"
    static let recurrenceParentId = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
    static let lastCompletedAt = Date(timeIntervalSince1970: 1_778_090_000)
    static let orderIndex = 42.5
    static let externalSourceID = "todoist:8237162"
    static let externalSourceMetadata = Data(#"{"source":"todoist","id":"8237162"}"#.utf8)
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
