import Foundation
import NexusCore
import NexusMeetings
import SwiftData

/// One-shot developer utility to deploy the CloudKit schema.
///
/// CloudKit only materializes a record type once a record of that type is exported,
/// so a freshly-enabled container that has only ever held tasks ends up with just
/// `CD_TaskItem` in its Development schema. Promoting that partial schema to
/// Production silently breaks sync for every other model (Production never
/// auto-creates types). To deploy a *complete* schema we insert one record of every
/// CloudKit-synced model, let `NSPersistentCloudKitContainer` export them (which
/// creates each record type in Development), then promote Development → Production.
///
/// Usage (Debug build, signed into iCloud):
///   1. Launch with `NEXUS_CLOUDKIT_ENABLED=1 NEXUS_SEED_CLOUDKIT_SCHEMA=1`.
///   2. Wait for export, confirm all record types in the CloudKit Console (Development).
///   3. Promote Development → Production (Console "Deploy Schema Changes…" or `cktool`).
///   4. Relaunch with `NEXUS_CLOUDKIT_ENABLED=1 NEXUS_UNSEED_CLOUDKIT_SCHEMA=1` to
///      delete the marker records (the deletions sync out, removing them everywhere).
///
/// The synced model set mirrors `NexusSchemaV7` (minus the local-only `ConflictLog`)
/// plus `MeetingsComposition.extraModels`. Agent models are not part of the synced
/// CloudKit configuration and are intentionally excluded.
enum CloudKitSchemaSeeder {
    static let marker = "\u{27C2}CKSEED\u{27C2}"
    /// Deterministic IDs so `unseed` can identify the marker `Link` (which has no
    /// string field) by its exact endpoints without touching real links.
    static let markerTaskID = UUID(uuidString: "0C5EED00-0000-0000-0000-000000000001")!
    static let markerProjectID = UUID(uuidString: "0C5EED00-0000-0000-0000-000000000002")!

    static func runIfRequested(context: ModelContext) {
        let env = ProcessInfo.processInfo.environment
        if env["NEXUS_UNSEED_CLOUDKIT_SCHEMA"] == "1" {
            unseed(context: context)
        } else if env["NEXUS_SEED_CLOUDKIT_SCHEMA"] == "1" {
            seed(context: context)
        }
    }

    /// Inserts one fully-populated marker of every CloudKit-synced model.
    ///
    /// CloudKit only creates a schema field when a NON-NIL value is exported, so a
    /// minimal init (e.g. `TaskItem(id:title:)`) leaves all optionals nil and they
    /// never materialize — producing a field-incomplete Production schema that makes
    /// `NSPersistentCloudKitContainer` fail to initialize ("Never successfully
    /// initialized", CKError partialFailure) and kills ALL sync. Each per-model
    /// factory below therefore sets every optional to a sentinel; non-optional fields
    /// already materialize from their defaults. Markers are also `deletedAt`-tagged so
    /// the app's `deletedAt == nil` queries hide them during the brief seed window.
    private static func seed(context: ModelContext) {
        let date = Date.now
        let data = Data([0x01])
        context.insert(markerTask(date: date, data: data))
        context.insert(markerProject(date: date))
        context.insert(markerSection(date: date))
        if let filter = markerSavedFilter(date: date) {
            context.insert(filter)
        }
        context.insert(markerLink())
        context.insert(QuotaLog(providerRaw: marker, day: date, promptTokens: 0, completionTokens: 0))
        context.insert(markerManifest())
        context.insert(markerDownloadEvent(date: date))
        context.insert(markerDebugItem(date: date))
        context.insert(markerMeeting(date: date, data: data))
        do {
            try context.save()
            NSLog(
                "[CKSEED] inserted one fully-populated record of each synced model — "
                    + "wait for CloudKit export, then check the Console (Development).")
        } catch {
            NSLog("[CKSEED] save failed: \(error)")
        }
    }

    /// `date` must be RECENT, not epoch: the launch-time `TombstonePurgeJob`
    /// (30-day retention, scoped to `TaskItem`) hard-deletes any TaskItem whose
    /// `deletedAt` is older than 30 days BEFORE CloudKit can export it — which
    /// silently drops every TaskItem-only field (`deletedAt`, `parentTaskID`,
    /// `projectID`, …) from the materialized schema. A `.now` tombstone is inside
    /// the retention window, so the marker survives long enough to export.
    private static func markerTask(date: Date, data: Data) -> TaskItem {
        let task = TaskItem(id: markerTaskID, title: marker)
        task.body = marker
        task.deletedAt = date
        task.dueAt = date
        task.startAt = date
        task.endAt = date
        task.snoozedUntil = date
        task.recurrenceRule = marker
        task.recurrenceParentId = markerTaskID
        task.lastCompletedAt = date
        task.parentTaskID = markerTaskID
        task.deadlineAt = date
        task.projectID = markerProjectID
        task.sectionID = markerProjectID
        task.orderIndex = 0
        task.externalSourceID = marker
        task.externalSourceMetadata = data
        return task
    }

    private static func markerProject(date: Date) -> Project {
        let project = Project(id: markerProjectID, name: marker)
        project.parentProjectID = markerProjectID
        project.archivedAt = date
        project.deletedAt = date
        return project
    }

    private static func markerSection(date: Date) -> Section {
        let section = Section(projectID: markerProjectID, name: marker)
        section.deletedAt = date
        return section
    }

    private static func markerSavedFilter(date: Date) -> SavedFilter? {
        guard let filter = try? SavedFilter(name: marker, definition: .unsorted) else { return nil }
        filter.deletedAt = date
        return filter
    }

    private static func markerLink() -> Link {
        let link = Link(from: (.task, markerTaskID), to: (.project, markerProjectID), linkKind: .mentions)
        link.order = 0
        return link
    }

    private static func markerManifest() -> ModelManifest {
        let manifest = ModelManifest(
            id: marker,
            hfPath: marker,
            family: marker,
            displayName: marker,
            sizeGB: 0,
            recommendedRAMGB: 0,
            contextLength: 0,
            supportsTools: false,
            supportsVision: false,
            supportedLocales: [marker],
            purpose: "chat"
        )
        manifest.temperatureOverride = 0
        manifest.maxTokensOverride = 0
        manifest.idleTimeoutSecondsOverride = 0
        manifest.systemPromptOverride = marker
        return manifest
    }

    private static func markerDownloadEvent(date: Date) -> ModelDownloadEvent {
        let event = ModelDownloadEvent(modelManifestID: marker, kind: marker, occurredAt: date)
        event.bytesTransferred = 0
        event.durationSeconds = 0
        event.errorMessage = marker
        return event
    }

    private static func markerDebugItem(date: Date) -> DebugItem {
        let debug = DebugItem(title: marker)
        debug.deletedAt = date
        return debug
    }

    private static func markerMeeting(date: Date, data: Data) -> Meeting {
        let meeting = Meeting(title: marker, startedAt: date, detectionSource: .manual)
        meeting.endedAt = date
        meeting.appBundleID = marker
        meeting.calendarEventID = marker
        meeting.processedAt = date
        meeting.participantsJSON = data
        meeting.languageCode = marker
        meeting.deletedAt = date
        meeting.externalSourceID = marker
        return meeting
    }

    private static func unseed(context: ModelContext) {
        deleteMarked(TaskItem.self, context) { $0.id == markerTaskID }
        deleteMarked(Project.self, context) { $0.id == markerProjectID }
        deleteMarked(Section.self, context) { $0.projectID == markerProjectID }
        deleteMarked(SavedFilter.self, context) { $0.name == marker }
        deleteMarked(Link.self, context) { $0.fromID == markerTaskID && $0.toID == markerProjectID }
        deleteMarked(QuotaLog.self, context) { $0.providerRaw == marker }
        deleteMarked(ModelManifest.self, context) { $0.id == marker }
        deleteMarked(ModelDownloadEvent.self, context) { $0.modelManifestID == marker }
        deleteMarked(DebugItem.self, context) { $0.title == marker }
        deleteMarked(Meeting.self, context) { $0.title == marker }

        do {
            try context.save()
            NSLog("[CKSEED] deleted marker records.")
        } catch {
            NSLog("[CKSEED] unseed save failed: \(error)")
        }
    }

    private static func deleteMarked<Model: PersistentModel>(
        _ type: Model.Type,
        _ context: ModelContext,
        where isMarker: (Model) -> Bool
    ) {
        let all = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        for model in all where isMarker(model) {
            context.delete(model)
        }
    }
}
