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
}
