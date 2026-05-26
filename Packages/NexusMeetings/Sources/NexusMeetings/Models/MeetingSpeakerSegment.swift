import Foundation

public struct MeetingSpeakerSegment: Codable, Sendable, Equatable {
    public let startMs: Int
    public let endMs: Int
    public let speaker: String
    public let text: String

    public init(startMs: Int, endMs: Int, speaker: String, text: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.speaker = speaker
        self.text = text
    }

    public static func encode(_ segments: [MeetingSpeakerSegment]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(segments)
    }

    public static func decode(_ data: Data) throws -> [MeetingSpeakerSegment] {
        if data.isEmpty { return [] }
        return try JSONDecoder().decode([MeetingSpeakerSegment].self, from: data)
    }
}
