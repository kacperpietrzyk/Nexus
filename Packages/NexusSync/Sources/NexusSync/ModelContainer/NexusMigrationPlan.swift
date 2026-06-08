import Foundation
import NexusCore
import SwiftData

/// Schema migration plan for the on-disk container.
///
/// Stages:
/// - V1 -> V2 lightweight (additive: `QuotaLog`).
/// - V2 -> V3 lightweight (additive: `TaskItem`; `DebugItem` retained vestigial).
/// - V3 -> V4 lightweight (additive: `TaskItem` external-source fields).
/// - V4 -> V5 lightweight (additive: `TaskItem.endAt`).
/// - V5 -> V6 lightweight (additive: task hierarchy/deadline/project fields and
///   Project/Section/SavedFilter entities).
/// - V6 -> V7 lightweight (additive: ModelManifest, ModelDownloadEvent).
/// - V7 -> V8 lightweight (additive: Comment entity; TaskItem.remindersData).
/// - V8 -> V9 lightweight (additive schema: `Note`, `TaskItem.noteRef`,
///   `Project.canonicalNoteRef`). The associated `TaskItem.body` -> `Note` DATA
///   move (spec §15) is NOT a migration stage — see below.
/// - V9 -> V10 lightweight (additive schema: `ScheduledBlock` entity +
///   `TaskItem.estimatedDurationSeconds` / `TaskItem.durationSourceRaw`; Calendar /
///   Motion-AI scheduler, spec §3/§4.1/§5). Pure additive — no data move.
/// - V10 -> V11 lightweight (additive schema: `Label` entity + `Project.statusRaw`
///   + `TaskItem.workflowStateRaw` / `TaskItem.assignedAgent`; Projects tier, spec
///   §4.4/§12). Pure additive — no data move. The system-label SEED is NOT a
///   migration stage (same reasoning as the body -> Note move below): it runs as
///   plain, idempotent, marker-gated post-open code in
///   `NexusModelContainer.seedSystemLabelsIfNeeded`.
///
/// WHY the body -> Note move is NOT a `.custom` migration stage (a deliberate
/// deviation from the spec's "custom stage" wording, forced by this codebase's
/// architecture — see `NexusModelContainer.migrateTaskBodiesToNotesIfNeeded`):
///   1. The production container is a *split* (synced + local-only)
///      two-configuration container, and `NexusModelContainer.makeContainer` DROPS
///      this plan on that path, relying on SwiftData lightweight *inference*. A
///      `.custom didMigrate` would therefore NEVER fire for real users (the
///      original `everyStageIsLightweight…` guard documents exactly this hazard).
///   2. A single-config plan-driven pre-pass also fails: plan-based staged
///      migration matches the on-disk store's version hashes against the plan's
///      versioned schemas, but the production store carries composition extras
///      (Meeting) that are never in those schemas (package cycle) — SwiftData
///      throws "unknown coordinator model version".
/// So the V8 -> V9 delta is lightweight-additive (the split inference open adds
/// the `Note` table + ref columns), and the data move runs as plain, idempotent,
/// marker-gated code over the already-open container in
/// `NexusModelContainer.migrateTaskBodiesToNotesIfNeeded`, proven end-to-end by
/// `SchemaV9MigrationTests.splitContainerMigratesTaskBodiesToNotesOnDisk`.
public enum NexusMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            NexusSchemaV1.self,
            NexusSchemaV2.self,
            NexusSchemaV3.self,
            NexusSchemaV4.self,
            NexusSchemaV5.self,
            NexusSchemaV6.self,
            NexusSchemaV7.self,
            NexusSchemaV8.self,
            NexusSchemaV9.self,
            NexusSchemaV10.self,
            NexusSchemaV11.self,
        ]
    }

    public static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV1.self,
                toVersion: NexusSchemaV2.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV2.self,
                toVersion: NexusSchemaV3.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV3.self,
                toVersion: NexusSchemaV4.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV4.self,
                toVersion: NexusSchemaV5.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV5.self,
                toVersion: NexusSchemaV6.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV6.self,
                toVersion: NexusSchemaV7.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV7.self,
                toVersion: NexusSchemaV8.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV8.self,
                toVersion: NexusSchemaV9.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV9.self,
                toVersion: NexusSchemaV10.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV10.self,
                toVersion: NexusSchemaV11.self
            ),
        ]
    }

    /// V8 -> V9 body -> Note data move (spec §15). Converts each `TaskItem` with
    /// non-empty legacy `body` into a free-role `Note`, links it via `noteRef`, and
    /// computes the denormalized `plainText` cache. Empty-body tasks get NO `Note`
    /// (lazy-by-content, spec §6/§8). `Project.canonicalNoteRef` is left nil.
    ///
    /// Invoked as plain code (NOT a `didMigrate` closure — see the type doc) by
    /// `NexusModelContainer.migrateTaskBodiesToNotesIfNeeded` on the already-open
    /// V9 container: `Note` is insertable and the retained legacy `TaskItem.body`
    /// column is still readable.
    ///
    /// Idempotent + safe no-op: skips tasks whose `body` is blank and tasks that
    /// already carry a `noteRef` (so a re-run, or a partially-completed prior run,
    /// never double-creates). A store with zero tasks yields no work.
    static func migrateTaskBodiesToNotes(in context: ModelContext) throws {
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        var didInsert = false

        for task in tasks {
            let body = task.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, task.noteRef == nil else { continue }

            let blocks = MarkdownBlockParser.parse(task.body)
            let note = Note(
                title: task.title,
                contentData: (try? NoteContentCoder.encode(blocks)) ?? Data(),
                plainText: NotePlainTextFlattener.plainText(for: blocks),
                role: .free
            )
            context.insert(note)
            task.noteRef = note.id
            didInsert = true
        }

        if didInsert {
            try context.save()
        }
    }

    /// V10 -> V11 system-label seed (spec §7/§12). Idempotently inserts the
    /// canonical `SystemLabel` set (feature/bug/infra/security in `domain`;
    /// needsDecision/decided in `gate`) with `isSystem = true`.
    ///
    /// Mirrors the data-safety logic of `LabelRepository.seedSystemLabels` but is
    /// NON-isolated (a plain static, like `migrateTaskBodiesToNotes`) so it can run
    /// from the off-`MainActor` post-open path in `NexusModelContainer.make`. It does
    /// NOT depend on `LabelRepository` (which is `@MainActor`); it touches only
    /// non-isolated `NexusCore` value/model types.
    ///
    /// Idempotent: each `SystemLabel` is matched case-insensitively by name against
    /// the existing non-soft-deleted `Label` rows (CloudKit forbids
    /// `@Attribute(.unique)`), and only the missing ones are created. A re-run, or a
    /// partially-completed prior run, never double-creates. A store already carrying
    /// the full set yields no work and no save.
    static func seedSystemLabels(in context: ModelContext) throws {
        let existing = try context.fetch(
            FetchDescriptor<Label>(predicate: #Predicate { label in label.deletedAt == nil })
        )
        var presentNames = Set(existing.map { $0.name.lowercased() })
        var didInsert = false

        for system in SystemLabel.allCases where !presentNames.contains(system.name.lowercased()) {
            let label = Label(
                name: system.name,
                glyphKey: system.glyphKey,
                group: system.group,
                isSystem: true
            )
            context.insert(label)
            presentNames.insert(system.name.lowercased())
            didInsert = true
        }

        if didInsert {
            try context.save()
        }
    }
}
