import Foundation
import NexusCore

/// Wire shape for `activity.get` (Tranche 2 Plan B, spec §6.3). `payloadJSON`
/// is passed through verbatim (the stored {"old":…,"new":…} blob) so the agent
/// can parse diffs without a second schema.
public struct ActivityEntryDTO: Codable, Sendable, Equatable {
    public let id: String
    public let itemID: String
    public let itemKind: String
    public let eventKind: String
    public let payloadJSON: String?
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case itemID = "item_id"
        case itemKind = "item_kind"
        case eventKind = "event_kind"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
    }

    @MainActor
    public init(from entry: ActivityEntry) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = entry.id.uuidString
        self.itemID = entry.itemID.uuidString
        self.itemKind = entry.itemKindRaw
        self.eventKind = entry.eventKindRaw
        self.payloadJSON = entry.payloadJSON
        self.createdAt = formatter.string(from: entry.createdAt)
    }
}
