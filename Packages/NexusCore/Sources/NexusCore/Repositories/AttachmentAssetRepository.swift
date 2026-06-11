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
        var descriptor = FetchDescriptor<AttachmentAsset>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first { $0.deletedAt == nil }
    }

    public func softDelete(_ asset: AttachmentAsset) throws {
        let stamp = now()
        asset.deletedAt = stamp
        asset.updatedAt = stamp
        try context.save()
    }
}
