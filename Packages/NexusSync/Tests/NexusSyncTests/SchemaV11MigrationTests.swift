import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

/// V10 -> V11 migration: additive registration of the `Label` structural-label
/// entity plus the additive `Project.statusRaw` / `TaskItem.workflowStateRaw` /
/// `TaskItem.assignedAgent` fields (Projects tier, spec §4.4/§12), and the
/// idempotent system-label SEED.
///
/// The whole V10 -> V11 delta is lightweight-additive: a shipped-V10 on-disk store
/// physically lacks the `Label` table (and the three additive columns); the V11
/// build's lightweight inference adds them in one pass. There is no data move. The
/// genuinely new structural delta at V11 is the **`Label` table** — the additive
/// columns on `Project`/`TaskItem` already live on the shared classes (so a seeded
/// "V10 store" carries them with their live-class defaults; these tests prove
/// round-trip, not literal column-fill on a physically-missing column).
///
/// The system-label seed runs as plain, marker-gated post-open code (NOT a
/// migration stage) in `NexusModelContainer.seedSystemLabelsIfNeeded`. These tests
/// prove (1) the schema shape, (2) `Label` is insertable on a fresh V11 store and
/// the additive fields round-trip with their defaults, (3) a real on-disk V10 store
/// with a composition-time synced extra survives the reopen through the REAL
/// production split container with no data loss AND gets the system labels seeded,
/// and (4) the seed is idempotent across two `make()` opens (and bypassing the
/// marker, against the same store).
@Suite struct SchemaV11MigrationTests {
    // MARK: - Schema shape

    @Test func v11AddsLabelToV10Models() {
        #expect(NexusSchemaV11.models.count == NexusSchemaV10.models.count + 1)
        #expect(NexusSchemaV11.models.contains { $0 == Label.self })
    }

    @Test func v11VersionIsHigherThanV10() {
        #expect(NexusSchemaV11.versionIdentifier > NexusSchemaV10.versionIdentifier)
    }

    @Test func migrationPlanIncludesV11Schema() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV11.self })
    }

    /// `Label` is a SYNCED partition (spec §4.4): labels mirror to the CloudKit
    /// private DB so they travel with the user's tasks/projects across devices. It
    /// must NOT slip into `localOnlyBaseline`. The on-disk crown-jewel test runs
    /// with CloudKit off (both partitions local), so it cannot tell the two apart —
    /// this is the one discriminating check that pins the requirement.
    @Test func labelIsASyncedPartitionNotLocalOnly() {
        let partitions = NexusModelContainer.modelPartitions(extraModels: [StubSyncedExtra.self])
        #expect(partitions.syncedModels.contains { String(describing: $0) == "Label" })
        #expect(!partitions.localOnlyModels.contains { String(describing: $0) == "Label" })
    }

    /// The V10 -> V11 stage is lightweight-additive (Label table + three additive
    /// columns). It MUST stay `.lightweight`: the production split container drops
    /// the plan and relies on inference, so a `.custom` stage here would never run
    /// for real users.
    @Test func v10ToV11StageIsLightweight() {
        let v10ToV11 = NexusMigrationPlan.stages
            .map { String(describing: $0) }
            .filter { $0.contains("V10") && $0.contains("V11") }
        #expect(v10ToV11.count == 1)
        #expect(v10ToV11.allSatisfy { $0.contains("lightweight") })
    }

    // MARK: - Fresh V11 store

    /// A fresh V11 store accepts `Label` inserts and round-trips the additive
    /// `Project.statusRaw` (default `backlog`) / `TaskItem.workflowStateRaw` (nil) /
    /// `TaskItem.assignedAgent` (nil) fields.
    @Test func freshV11StoreAllowsLabelInsertsAndAdditiveFieldDefaults() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV11.models, version: NexusSchemaV11.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let label = Label(name: "feature", glyphKey: "sparkles", group: .domain, isSystem: true)
        context.insert(label)
        let task = TaskItem(title: "Plain GTD task")
        context.insert(task)
        let project = Project(name: "ThreatForge")
        context.insert(project)
        try context.save()

        let labels = try context.fetch(FetchDescriptor<Label>())
        #expect(labels.count == 1)
        let fetchedLabel = try #require(labels.first)
        #expect(fetchedLabel.kind == .label)
        #expect(fetchedLabel.group == .domain)
        #expect(fetchedLabel.isSystem)

        // Additive TaskItem fields default to nil (GTD task / self).
        let task0 = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first)
        #expect(task0.workflowStateRaw == nil)
        #expect(task0.workflowState == nil)
        #expect(task0.assignedAgent == nil)

        // Additive Project field defaults to backlog.
        let project0 = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        #expect(project0.statusRaw == ProjectStatus.backlog.rawValue)
        #expect(project0.status == .backlog)
    }

    /// Soft-delete works on `Label` (consistent with the other models): a deleted
    /// label carries `deletedAt` and remains physically present (filtered by
    /// callers, not purged).
    @Test func labelSoftDeleteSetsDeletedAt() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV11.models, version: NexusSchemaV11.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let label = Label(name: "infra", group: .domain)
        #expect(label.deletedAt == nil)
        context.insert(label)
        try context.save()

        label.deletedAt = Date(timeIntervalSince1970: 1_790_100_000)
        try context.save()

        let labels = try context.fetch(FetchDescriptor<Label>())
        #expect(labels.count == 1)
        #expect(labels.first?.deletedAt == Date(timeIntervalSince1970: 1_790_100_000))
    }

    // MARK: - Seed (non-isolated static, in-memory)

    /// `NexusMigrationPlan.seedSystemLabels` inserts the full `SystemLabel` set with
    /// `isSystem = true` and the correct groups.
    @Test func seedSystemLabelsCreatesCanonicalSetWithCorrectGroups() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV11.models, version: NexusSchemaV11.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        try NexusMigrationPlan.seedSystemLabels(in: context)

        let labels = try context.fetch(FetchDescriptor<Label>())
        #expect(labels.count == SystemLabel.allCases.count)
        let allSystem = labels.allSatisfy { $0.isSystem }
        #expect(allSystem)

        let byName = Dictionary(uniqueKeysWithValues: labels.map { ($0.name, $0) })
        #expect(byName["feature"]?.group == .domain)
        #expect(byName["bug"]?.group == .domain)
        #expect(byName["infra"]?.group == .domain)
        #expect(byName["security"]?.group == .domain)
        #expect(byName["needsDecision"]?.group == .gate)
        #expect(byName["decided"]?.group == .gate)
    }

    /// Seed idempotency at the data layer (no marker): running the seed twice over
    /// the SAME context yields exactly one copy of each system label.
    @Test func seedSystemLabelsIsIdempotentWhenRunTwice() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV11.models, version: NexusSchemaV11.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        try NexusMigrationPlan.seedSystemLabels(in: context)
        try NexusMigrationPlan.seedSystemLabels(in: context)

        let labels = try context.fetch(FetchDescriptor<Label>())
        #expect(labels.count == SystemLabel.allCases.count)
        let names = Set(labels.map(\.name))
        #expect(names.count == labels.count)  // no duplicates
    }

    /// Seed does not re-create a label whose name already exists (case-insensitive),
    /// and does not resurrect / re-count user rows that share a name. A pre-existing
    /// user `feature` (lowercase match) blocks the system `feature` insert.
    @Test func seedIsNotBlockedByUserLabelOfSameName() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV11.models, version: NexusSchemaV11.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let userLabel = Label(name: "Feature", group: .free, isSystem: false)
        context.insert(userLabel)
        try context.save()

        try NexusMigrationPlan.seedSystemLabels(in: context)

        // P4: the user's free "Feature" must NOT suppress the canonical system
        // "feature" (+ its stable id) — they coexist.
        let featureNamed = try context.fetch(FetchDescriptor<Label>())
            .filter { $0.name.lowercased() == "feature" }
        #expect(featureNamed.count == 2)
        #expect(featureNamed.contains { $0.id == SystemLabel.feature.id && $0.isSystem })
        #expect(featureNamed.contains { !$0.isSystem })
        // The full system set seeded alongside the one extra user label.
        let all = try context.fetch(FetchDescriptor<Label>())
        #expect(all.count == SystemLabel.allCases.count + 1)
    }

    // MARK: - Production split-container path (on-disk, crown jewel)

    /// THE deliverable. Seeds a real on-disk store stamped at V10 holding a
    /// composition-time synced extra (`StubSyncedExtra`, the Meeting stand-in), then
    /// reopens through the REAL production entry `NexusModelContainer.make` (the
    /// split synced + local-only container that DROPS the migration plan and relies
    /// on lightweight inference). Proves:
    ///   1. the `Label` table is inferred and the system labels are SEEDED through
    ///      `make()` (post-open marker-gated seed fired),
    ///   2. a new `Label` is insertable on the migrated store,
    ///   3. the Meeting stand-in row SURVIVED (no destructive migration),
    ///   4. the additive `TaskItem`/`Project` columns round-trip with defaults.
    @MainActor
    @Test func splitContainerInfersV10ToV11AndSeedsSystemLabelsOnDisk() throws {
        let storeURL = temporaryV11StoreURL(prefix: "nexus-v10-to-v11-additive")
        defer { cleanupV11Stores(at: storeURL) }
        defer { clearV11Markers(for: storeURL) }

        let taskID = UUID()
        let projectID = UUID()
        try seedV10SyncedStore(at: storeURL, taskID: taskID, projectID: projectID)

        // Reopen through the REAL production entry. `make()` emits the split
        // synced + local-only container (dropping the plan → lightweight inference
        // adds the Label table + the three additive columns) and runs the
        // post-open system-label seed.
        let container = try NexusModelContainer.make(
            environment: V11MigrationTestEnvironment(),
            fileURL: storeURL,
            extraModels: [StubSyncedExtra.self]
        )
        let context = ModelContext(container)

        // (1) System labels seeded through make().
        let labels = try context.fetch(FetchDescriptor<Label>())
        #expect(labels.count == SystemLabel.allCases.count)
        let allSystem = labels.allSatisfy { $0.isSystem }
        #expect(allSystem)
        #expect(Set(labels.map(\.name)) == Set(SystemLabel.allCases.map(\.name)))

        // (2) Label is insertable on the migrated store.
        let userLabel = Label(name: "custom-tag", group: .free, isSystem: false)
        context.insert(userLabel)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Label>()).count == SystemLabel.allCases.count + 1)

        // (3) Meeting stand-in survived (no destructive migration).
        let survivors = try context.fetch(FetchDescriptor<StubSyncedExtra>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.label == "keep me across V11")

        // (4) Additive columns round-trip with defaults.
        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == taskID })
        #expect(task.workflowStateRaw == nil)
        #expect(task.assignedAgent == nil)
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first { $0.id == projectID })
        #expect(project.statusRaw == ProjectStatus.backlog.rawValue)
    }

    /// Seed idempotency through the production entry: opening the SAME on-disk store
    /// twice via `make()` yields exactly one copy of each system label (the marker
    /// short-circuits the second open). Then, clearing the marker and re-running the
    /// post-open seed directly STILL yields no duplicates — proving the data-layer
    /// idempotency, not merely the marker no-op.
    @MainActor
    @Test func systemLabelSeedIsIdempotentAcrossOpensAndBypassingMarker() throws {
        let storeURL = temporaryV11StoreURL(prefix: "nexus-v11-seed-idempotent")
        defer { cleanupV11Stores(at: storeURL) }
        defer { clearV11Markers(for: storeURL) }

        try seedV10SyncedStore(at: storeURL, taskID: UUID(), projectID: UUID())

        let env = V11MigrationTestEnvironment()
        let first = try NexusModelContainer.make(environment: env, fileURL: storeURL, extraModels: [StubSyncedExtra.self])
        let firstCount = try ModelContext(first).fetch(FetchDescriptor<Label>()).count
        #expect(firstCount == SystemLabel.allCases.count)

        // Second open: marker short-circuits the seed; count unchanged.
        let second = try NexusModelContainer.make(environment: env, fileURL: storeURL, extraModels: [StubSyncedExtra.self])
        let secondCount = try ModelContext(second).fetch(FetchDescriptor<Label>()).count
        #expect(secondCount == SystemLabel.allCases.count)

        // Bypass the marker and re-seed directly — data-layer idempotency holds.
        UserDefaults.standard.removeObject(
            forKey: NexusModelContainer.systemLabelSeedCompletionKey(for: storeURL)
        )
        try NexusModelContainer.seedSystemLabelsIfNeeded(container: second, storeURL: storeURL)
        let thirdCount = try ModelContext(second).fetch(FetchDescriptor<Label>()).count
        #expect(thirdCount == SystemLabel.allCases.count)
    }
}

// MARK: - Fixtures

private struct V11MigrationTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"
}

/// Seeds a synced (main) store stamped at V10 with one `TaskItem`, one `Project`,
/// and a composition-time synced extra entity. Mirrors what the split container
/// physically writes to the main store URL before V11 lands.
@MainActor
private func seedV10SyncedStore(at url: URL, taskID: UUID, projectID: UUID) throws {
    let schema = NexusSchemaV10.schema(extraModels: [StubSyncedExtra.self])
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ]
    )
    let context = ModelContext(container)

    let task = TaskItem(title: "Pre-V11 task")
    task.id = taskID
    context.insert(task)

    let project = Project(name: "Pre-V11 project")
    project.id = projectID
    context.insert(project)

    context.insert(StubSyncedExtra(label: "keep me across V11"))
    try context.save()
}

private func temporaryV11StoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupV11Stores(at storeURL: URL) {
    let urls = [storeURL, NexusModelContainer.localOnlyStoreURL(for: storeURL)]
    for url in urls {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
    }
}

/// Clears the per-store post-open markers so a reused tmpdir path never carries a
/// marker into another run (the body -> Note marker is exercised by `make()` even
/// on a fresh path; the system-label seed marker likewise).
private func clearV11Markers(for storeURL: URL) {
    UserDefaults.standard.removeObject(
        forKey: NexusModelContainer.taskBodyToNoteMigrationCompletionKey(for: storeURL)
    )
    UserDefaults.standard.removeObject(
        forKey: NexusModelContainer.systemLabelSeedCompletionKey(for: storeURL)
    )
}
