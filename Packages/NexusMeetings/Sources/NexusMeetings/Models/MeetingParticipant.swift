import Foundation

public struct MeetingParticipant: Codable, Sendable, Equatable {
    public let speakerID: String
    public let displayName: String

    public init(speakerID: String, displayName: String) {
        self.speakerID = speakerID
        self.displayName = displayName
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
