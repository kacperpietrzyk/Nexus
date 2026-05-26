import Foundation
import SwiftData

@Model
public final class MeetingAudioStorage {
    // Local-only entity, never synced - `.unique` is permitted here.
    @Attribute(.unique) public var meetingID: UUID
    public var folderURL: URL
    /// Raw value of `RetentionPolicy`.
    public var retentionPolicy: String
    public var expiresAt: Date?
    public var totalBytes: Int
    public var hasAudio: Bool
    public var createdAt: Date

    public enum RetentionPolicy: String, Sendable, Codable, CaseIterable {
        case days7 = "7d"
        case days30 = "30d"
        case forever
        case never
    }

    public init(
        meetingID: UUID,
        folderURL: URL,
        retentionPolicy: RetentionPolicy,
        totalBytes: Int = 0,
        hasAudio: Bool = true,
        createdAt: Date = Date()
    ) {
        self.meetingID = meetingID
        self.folderURL = folderURL
        self.retentionPolicy = retentionPolicy.rawValue
        self.totalBytes = totalBytes
        self.hasAudio = hasAudio
        self.createdAt = createdAt
        self.expiresAt = Self.computeExpiry(policy: retentionPolicy, createdAt: createdAt)
    }

    public func updateRetention(_ policy: RetentionPolicy) {
        self.retentionPolicy = policy.rawValue
        self.expiresAt = Self.computeExpiry(policy: policy, createdAt: createdAt)
    }

    private static func computeExpiry(policy: RetentionPolicy, createdAt: Date) -> Date? {
        switch policy {
        case .days7: return createdAt.addingTimeInterval(7 * 86_400)
        case .days30: return createdAt.addingTimeInterval(30 * 86_400)
        case .forever: return nil
        case .never: return createdAt.addingTimeInterval(-1)
        }
    }
}
