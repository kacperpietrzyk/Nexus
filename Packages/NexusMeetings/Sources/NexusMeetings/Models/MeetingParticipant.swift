import Foundation

public struct MeetingParticipant: Codable, Sendable, Equatable {
    public let speakerID: String
    public let displayName: String
    /// The `Person` this speaker was manually assigned to, when the user picked an
    /// existing contact in the rename sheet (#3). `nil` for free-text labels and for
    /// legacy participants persisted before this field existed — synthesized
    /// `Codable` uses `decodeIfPresent` for an `Optional`, so old `participantsJSON`
    /// missing the key decodes to `nil` (back-compatible, no SwiftData migration).
    public let personID: UUID?

    public init(speakerID: String, displayName: String, personID: UUID? = nil) {
        self.speakerID = speakerID
        self.displayName = displayName
        self.personID = personID
    }

    public static func encode(_ participants: [MeetingParticipant]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(participants)
    }

    public static func decode(_ data: Data) throws -> [MeetingParticipant] {
        if data.isEmpty { return [] }
        return try JSONDecoder().decode([MeetingParticipant].self, from: data)
    }
}
