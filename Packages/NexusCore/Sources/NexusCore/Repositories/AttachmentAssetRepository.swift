import Foundation
import SwiftData

@MainActor
public final class AttachmentAssetRepository {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    public func insert(_ asset: AttachmentAsset) throws {
        context.insert(asset)
        try context.save()
    }

    public func find(id: UUID) throws -> AttachmentAsset? {
        // No `fetchLimit`: on a synced store a soft-deleted CloudKit twin can share
        // the id and sort first, so a `fetchLimit = 1` + in-memory filter would
        // return nil for a LIVE asset. Fetch all rows for the id and pick the live
        // (non-deleted) one. (Twin volume is bounded; single-user scale is fine.)
        let descriptor = FetchDescriptor<AttachmentAsset>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first { $0.deletedAt == nil }
    }

    public func softDelete(_ asset: AttachmentAsset) throws {
        let stamp = now()
        asset.deletedAt = stamp
        asset.updatedAt = stamp
        try context.save()
    }
}
