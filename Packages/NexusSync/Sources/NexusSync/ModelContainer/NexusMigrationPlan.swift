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
/// - V11 -> V12 lightweight (additive schema: `Person` contact-record entity;
///   People / Contacts module, spec §4.1/§8). Pure additive — no data move. The new
///   `ItemKind.person` / `LinkKind.attendee` raw enum cases are stored as existing
///   `String` columns on the `Link` table and need no schema change. The optional
///   `participantsJSON` -> `Person` BACKFILL is NOT a migration stage (same reasoning
///   as the body -> Note move below): it runs as plain, idempotent code over an
///   already-open container in `backfillPeopleFromMeetingParticipants` and is deferred
///   to first-launch bootstrap because it needs the concrete `Meeting` type (a
///   composition-time extra NexusSync cannot import).
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
            NexusSchemaV12.self,
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
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV11.self,
                toVersion: NexusSchemaV12.self
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

    /// Minimal decode shape for one `Meeting.participantsJSON` entry. Deliberately
    /// NOT `MeetingParticipant` (that lives in NexusMeetings, which NexusSync cannot
    /// import). Decoding only the `displayName` is forward-compatible: extra keys in
    /// the persisted JSON (e.g. `speakerID`) are ignored.
    private struct BackfillParticipant: Decodable {
        let displayName: String
    }

    /// V11 -> V12 People backfill (spec §8). For each existing meeting's
    /// `participantsJSON`, ensures a `Person` exists for every unique participant
    /// `displayName` and a `Link(.attendee)` from that meeting to the person.
    ///
    /// Generic over the concrete `Meeting` model `M` (passed by `participantsKeyPath`
    /// + `idKeyPath`) because NexusSync cannot import `Meeting` (composition-time
    /// extra / package cycle) — so the INVOCATION is deferred to first-launch
    /// bootstrap where `Meeting.self` is nameable, NOT wired into
    /// `NexusModelContainer.make`. Invoked as plain code (NOT a `didMigrate` closure —
    /// see the type doc / `migrateTaskBodiesToNotes`) on an already-open V12 container:
    /// `Person` and `Link` are insertable and the `participantsJSON` column is readable.
    ///
    /// Idempotency (spec §8 / §10):
    ///   - `Person` is deduplicated GLOBALLY by an EXACT, non-soft-deleted
    ///     `displayName` match (find-or-create) — NOT the fuzzy soft-match, so two
    ///     runs yield the same set. `externalSourceID` stays nil (the key here is the
    ///     name, not an external id).
    ///   - the `.attendee` edge is created only if an identical edge does not already
    ///     exist (matched on from/to/linkKind), so a re-run never double-links.
    ///   - a meeting with nil/empty `participantsJSON` contributes 0 people and 0
    ///     links; blank display names are skipped.
    /// A store with zero meetings (or zero participants) yields no work and no save.
    static func backfillPeopleFromMeetingParticipants<M: PersistentModel>(
        meetingType _: M.Type,
        participantsKeyPath: KeyPath<M, Data?>,
        idKeyPath: KeyPath<M, UUID>,
        in context: ModelContext
    ) throws {
        let meetings = try context.fetch(FetchDescriptor<M>())
        guard !meetings.isEmpty else { return }

        // Index existing (non-soft-deleted) people by display name for find-or-create.
        var peopleByName: [String: Person] = [:]
        for person in try context.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.deletedAt == nil })
        ) where peopleByName[person.displayName] == nil {
            peopleByName[person.displayName] = person
        }

        // Index existing attendee edges by their stable from/to identity. The
        // `linkKind` enum case cannot be compared inside a `#Predicate` key path, so
        // filter in Swift after the fetch.
        var existingAttendeeEdges = Set<String>()
        for link in try context.fetch(FetchDescriptor<Link>()) where link.linkKind == .attendee {
            existingAttendeeEdges.insert("\(link.fromID.uuidString):\(link.toID.uuidString)")
        }

        var didInsert = false

        for meeting in meetings {
            guard let data = meeting[keyPath: participantsKeyPath], !data.isEmpty,
                let participants = try? JSONDecoder().decode([BackfillParticipant].self, from: data)
            else { continue }

            let meetingID = meeting[keyPath: idKeyPath]
            var seenInMeeting = Set<String>()

            for participant in participants {
                let name = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seenInMeeting.insert(name).inserted else { continue }

                let person: Person
                if let existing = peopleByName[name] {
                    person = existing
                } else {
                    let created = Person(displayName: name)
                    context.insert(created)
                    peopleByName[name] = created
                    person = created
                    didInsert = true
                }

                let edgeKey = "\(meetingID.uuidString):\(person.id.uuidString)"
                guard existingAttendeeEdges.insert(edgeKey).inserted else { continue }
                context.insert(
                    Link(from: (.meeting, meetingID), to: (.person, person.id), linkKind: .attendee)
                )
                didInsert = true
            }
        }

        if didInsert {
            try context.save()
        }
    }
}
