import CloudKit
import Foundation

/// Custom CloudKit zone scaffolding. **Not used by the SwiftData mirror** —
/// `ModelConfiguration(cloudKitDatabase: .private(...))` auto-creates and manages its own
/// system zone (`com.apple.coredata.cloudkit.zone`), which is what holds Linkable records.
///
/// This zone is reserved for **Phase 1+ direct-CloudKit operations** that bypass SwiftData:
/// uploading meeting audio as `CKAsset`, sending sync-nudge records, and any
/// `CKFetchRecordZoneChangesOperation` we want to drive ourselves for efficient delta sync of
/// non-SwiftData payloads.
public enum NexusZone {
    public static let zoneName = "NexusZone"

    public static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public static func recordZone() -> CKRecordZone {
        CKRecordZone(zoneID: zoneID)
    }

    /// Ensures the zone exists in the user's private database. Safe to call repeatedly — the
    /// `CKModifyRecordZonesOperation` is idempotent on the server side. Phase 0b ships the call;
    /// Phase 1+ wires it into app launch behind `NexusEnvironment.cloudKitEnabled` once a
    /// direct-CloudKit consumer (e.g. meeting-audio CKAsset writer) needs the zone.
    public static func ensureExists(in container: CKContainer) async throws {
        let database = container.privateCloudDatabase
        let op = CKModifyRecordZonesOperation(
            recordZonesToSave: [recordZone()],
            recordZoneIDsToDelete: nil
        )
        op.qualityOfService = .userInitiated
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            database.add(op)
        }
    }
}
