import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

/// V12 -> V13 migration: the Tranche-2 parity batch (spec
/// `2026-06-11-tranche2-v8-parity-batch.md` §3). Additive registration of the
/// `Cycle` + `ActivityEntry` entities plus four additive defaulted/optional
/// columns on `TaskItem`/`Note`.
///
/// The whole V12 -> V13 delta is lightweight-additive: a shipped-V12 on-disk
/// store physically lacks the two new tables and four new columns; the V13
/// build's lightweight inference adds them in one pass. There is NO data move
/// and NO backfill — every new field starts nil/defaulted and every new table
/// starts empty, so (unlike V9/V11/V12) this bump has NO marker-gated
/// post-open bootstrap step. The new `ItemKind.cycle` / `NoteRole.template`
/// raw enum cases ride existing `String`-backed columns and need no schema
/// change (the V12 `ItemKind.person` precedent).
@Suite struct SchemaV13MigrationTests {
    // MARK: - Schema shape

    @Test func v13AddsCycleAndActivityEntryToV12Models() {
        #expect(NexusSchemaV13.models.count == NexusSchemaV12.models.count + 2)
        #expect(NexusSchemaV13.models.contains { $0 == Cycle.self })
        #expect(NexusSchemaV13.models.contains { $0 == ActivityEntry.self })
    }

    @Test func v13VersionIsHigherThanV12() {
        #expect(NexusSchemaV13.versionIdentifier > NexusSchemaV12.versionIdentifier)
        #expect(NexusSchemaV13.versionIdentifier == Schema.Version(13, 0, 0))
    }

    @Test func migrationPlanIncludesV13Schema() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV13.self })
    }

    /// The V12 -> V13 stage is lightweight-additive. It MUST stay
    /// `.lightweight`: the production split container drops the plan and
    /// relies on inference, so a `.custom` stage here would never run for
    /// real users (the architectural hazard the plan-type doc pins).
    @Test func v12ToV13StageIsLightweight() {
        let v12ToV13 = NexusMigrationPlan.stages
            .map { String(describing: $0) }
            .filter { $0.contains("V12") && $0.contains("V13") }
        #expect(v12ToV13.count == 1)
        #expect(v12ToV13.allSatisfy { $0.contains("lightweight") })
    }

    // MARK: - Partitions (synced, NOT local-only)

    /// `Cycle` is a SYNCED partition: sprints travel with the user's tasks
    /// across devices (CloudKit private DB). It must NOT slip into
    /// `localOnlyBaseline`. The on-disk crown-jewel test runs with CloudKit
    /// off (both partitions local), so it cannot tell the two apart — this is
    /// the discriminating check (the V12 `personIsASyncedPartition` pattern).
    @Test func cycleIsASyncedPartitionNotLocalOnly() {
        let partitions = NexusModelContainer.modelPartitions(extraModels: [StubSyncedExtra.self])
        #expect(partitions.syncedModels.contains { String(describing: $0) == "Cycle" })
        #expect(!partitions.localOnlyModels.contains { String(describing: $0) == "Cycle" })
    }

    /// Same pin for `ActivityEntry` (the audit log syncs — events recorded on
    /// one device render on another).
    @Test func activityEntryIsASyncedPartitionNotLocalOnly() {
        let partitions = NexusModelContainer.modelPartitions(extraModels: [StubSyncedExtra.self])
        #expect(partitions.syncedModels.contains { String(describing: $0) == "ActivityEntry" })
        #expect(!partitions.localOnlyModels.contains { String(describing: $0) == "ActivityEntry" })
    }

    // MARK: - Fresh V13 store (persist / fetch)

    /// A fresh V13 store accepts `Cycle` + `ActivityEntry` inserts and
    /// round-trips their fields. Proves the additive entities persist and fetch.
    @Test func freshV13StoreRoundTripsCycleAndActivityEntry() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV13.models, version: NexusSchemaV13.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let taskID = UUID()
        let cycle = Cycle(
            name: "Sprint 1",
            startAt: Date(timeIntervalSince1970: 1_700_000_000),
            endAt: Date(timeIntervalSince1970: 1_700_600_000),
            status: .active
        )
        context.insert(cycle)
        context.insert(
            ActivityEntry(
                itemID: taskID,
                itemKind: .task,
                eventKind: .workflowChanged,
                payloadJSON: "{\"old\":\"todo\",\"new\":\"inProgress\"}"
            )
        )
        try context.save()

        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        #expect(cycles.count == 1)
        #expect(cycles.first?.kind == .cycle)
        #expect(cycles.first?.status == .active)

        let events = try context.fetch(FetchDescriptor<ActivityEntry>())
        #expect(events.count == 1)
        #expect(events.first?.itemID == taskID)
        #expect(events.first?.eventKind == .workflowChanged)
        #expect(events.first?.payloadJSON == "{\"old\":\"todo\",\"new\":\"inProgress\"}")
    }

    /// A fresh V13 store gives plain `TaskItem`/`Note` rows the defaulted new
    /// columns (the additive-column half of the delta).
    @Test func freshV13StoreDefaultsNewTaskAndNoteColumns() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV13.models, version: NexusSchemaV13.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        context.insert(TaskItem(title: "plain"))
        context.insert(Note(title: "plain note"))
        try context.save()

        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first)
        #expect(task.cycleID == nil)
        #expect(!task.isTemplate)

        let note = try #require(try context.fetch(FetchDescriptor<Note>()).first)
        #expect(note.propertiesJSON == nil)
        #expect(note.folderPath == nil)
    }

    // MARK: - Production split-container path (on-disk, crown jewel)

    /// THE deliverable. Seeds a real on-disk store stamped at V12 holding a
    /// `TaskItem`, a `Note`, a `Project`, and a composition-time synced extra
    /// (`StubSyncedExtra`, the Meeting stand-in), then reopens through the
    /// REAL production entry `NexusModelContainer.make` (the split synced +
    /// local-only container that DROPS the migration plan and relies on
    /// lightweight inference). Proves the V12 -> V13 delta is additive with NO
    /// data loss:
    ///   1. the `Cycle` + `ActivityEntry` tables are inferred and insertable
    ///      on the migrated store,
    ///   2. the pre-V13 `TaskItem` survived intact with the new columns
    ///      DEFAULTED (`isTemplate == false`, `cycleID == nil`),
    ///   3. the pre-V13 `Note` survived intact with the new columns DEFAULTED
    ///      (`propertiesJSON == nil`, `folderPath == nil`),
    ///   4. the Meeting stand-in row SURVIVED (no destructive migration),
    ///   5. the V11 system labels are present (prior tiers not regressed).
    @MainActor
    @Test func splitContainerInfersV12ToV13AdditiveExpansionOnDisk() throws {
        let storeURL = temporaryV13StoreURL(prefix: "nexus-v12-to-v13-additive")
        defer { cleanupV13Stores(at: storeURL) }
        defer { clearV13Markers(for: storeURL) }

        let taskID = UUID()
        let noteID = UUID()
        try seedV12SyncedStore(at: storeURL, taskID: taskID, noteID: noteID)

        // Reopen through the REAL production entry. `make()` emits the split
        // synced + local-only container (dropping the plan -> lightweight
        // inference adds the Cycle/ActivityEntry tables + the four columns).
        let container = try NexusModelContainer.make(
            environment: V13MigrationTestEnvironment(),
            fileURL: storeURL,
            extraModels: [StubSyncedExtra.self]
        )
        let context = ModelContext(container)

        // (1) New tables inferred + insertable on the migrated store.
        #expect(try context.fetch(FetchDescriptor<Cycle>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActivityEntry>()).isEmpty)
        context.insert(Cycle(name: "Sprint 1", startAt: .now, endAt: .now))
        context.insert(ActivityEntry(itemID: taskID, itemKind: .task, eventKind: .created))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ActivityEntry>()).count == 1)

        // (2) Pre-V13 TaskItem survived with the new columns DEFAULTED.
        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == taskID })
        #expect(task.title == "Pre-V13 task")
        #expect(!task.isTemplate)
        #expect(task.cycleID == nil)

        // (3) Pre-V13 Note survived with the new columns DEFAULTED (nil).
        let note = try #require(try context.fetch(FetchDescriptor<Note>()).first { $0.id == noteID })
        #expect(note.title == "Pre-V13 note")
        #expect(note.propertiesJSON == nil)
        #expect(note.folderPath == nil)
        #expect(note.properties.isEmpty)

        // (4) Meeting stand-in survived (no destructive migration).
        let survivors = try context.fetch(FetchDescriptor<StubSyncedExtra>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.label == "keep me across V13")

        // (5) V11 system labels present (prior tier not regressed).
        let labels = try context.fetch(FetchDescriptor<Label>())
        #expect(labels.count == SystemLabel.allCases.count)
    }
}

// MARK: - On-disk fixtures

private struct V13MigrationTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"
}

/// Seeds a synced (main) store stamped at V12 with one `TaskItem`, one `Note`,
/// one `Project`, and a composition-time synced extra entity. Mirrors what the
/// split container physically writes to the main store URL before V13 lands.
@MainActor
private func seedV12SyncedStore(at url: URL, taskID: UUID, noteID: UUID) throws {
    let schema = NexusSchemaV12.schema(extraModels: [StubSyncedExtra.self])
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ]
    )
    let context = ModelContext(container)

    let task = TaskItem(title: "Pre-V13 task")
    task.id = taskID
    context.insert(task)

    let note = Note(title: "Pre-V13 note", plainText: "pre-v13 body")
    note.id = noteID
    context.insert(note)

    context.insert(Project(name: "Pre-V13 project"))
    context.insert(StubSyncedExtra(label: "keep me across V13"))
    try context.save()
}

private func temporaryV13StoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupV13Stores(at storeURL: URL) {
    let urls = [storeURL, NexusModelContainer.localOnlyStoreURL(for: storeURL)]
    for url in urls {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
    }
}

/// Clears the per-store post-open markers so a reused tmpdir path never
/// carries a marker into another run (`make()` exercises both the body -> Note
/// conversion and the system-label seed even on a fresh path). V13 itself adds
/// NO new marker — there is no V13 bootstrap step.
private func clearV13Markers(for storeURL: URL) {
    UserDefaults.standard.removeObject(
        forKey: NexusModelContainer.taskBodyToNoteMigrationCompletionKey(for: storeURL)
    )
    UserDefaults.standard.removeObject(
        forKey: NexusModelContainer.systemLabelSeedCompletionKey(for: storeURL)
    )
}
