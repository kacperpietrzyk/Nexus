import Foundation
import SwiftData

/// Synced metadata for an app-managed attachment file.
///
/// The binary payload lives outside SwiftData under the app attachments root.
/// This row is CloudKit-safe metadata only; graph edges can point at it by
/// `ItemKind.attachment` without making attachments a first-class `Linkable`.
@Model
public final class AttachmentAsset {
    public var id: UUID = UUID()
    public var originalFilename: String = ""
    public var mimeType: String = ""
    public var byteCount: Int = 0
    public var sha256: String = ""
    public var storagePath: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        originalFilename: String,
        mimeType: String,
        byteCount: Int,
        sha256: String,
        storagePath: String,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.storagePath = storagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
