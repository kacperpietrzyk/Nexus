import Foundation
import NexusCore

/// Wire shape for an `AttachmentAsset` returned by the `attachments.*` tools.
/// `storagePath`/`sha256` are intentionally omitted — callers reference assets by
/// `id`, and the on-disk layout is an app-private detail.
public struct AttachmentDTO: Codable, Sendable, Equatable {
    public let id: String
    public let filename: String
    public let contentType: String
    public let byteSize: Int
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, filename
        case contentType = "content_type"
        case byteSize = "byte_size"
        case createdAt = "created_at"
    }

    public init(from asset: AttachmentAsset) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = asset.id.uuidString
        self.filename = asset.originalFilename
        self.contentType = asset.mimeType
        self.byteSize = asset.byteCount
        self.createdAt = formatter.string(from: asset.createdAt)
    }
}
