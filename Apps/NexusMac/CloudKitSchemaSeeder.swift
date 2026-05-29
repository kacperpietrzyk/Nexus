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

    private static func seed(context: ModelContext) {
        context.insert(TaskItem(id: markerTaskID, title: marker))
        context.insert(Project(id: markerProjectID, name: marker))
        context.insert(Section(projectID: markerProjectID, name: marker))
        if let filter = try? SavedFilter(name: marker, definition: .unsorted) {
            context.insert(filter)
        }
        context.insert(Link(from: (.task, markerTaskID), to: (.project, markerProjectID), linkKind: .mentions))
        context.insert(QuotaLog(providerRaw: marker, day: .now, promptTokens: 0, completionTokens: 0))
        context.insert(
            ModelManifest(
                id: marker,
                hfPath: marker,
                family: marker,
                displayName: marker,
                sizeGB: 0,
                recommendedRAMGB: 0,
                contextLength: 0,
                supportsTools: false,
                supportsVision: false,
                supportedLocales: [],
                purpose: "chat"
            )
        )
        context.insert(ModelDownloadEvent(modelManifestID: marker, kind: marker, occurredAt: .now))
        context.insert(DebugItem(title: marker))
        context.insert(Meeting(title: marker, startedAt: .now, detectionSource: .manual))

        do {
            try context.save()
            NSLog("[CKSEED] inserted one of each synced model — wait for CloudKit export, then check the Console (Development).")
        } catch {
            NSLog("[CKSEED] save failed: \(error)")
        }
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
