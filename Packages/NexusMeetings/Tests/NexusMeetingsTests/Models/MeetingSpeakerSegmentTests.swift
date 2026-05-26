import Foundation
import Testing

@testable import NexusMeetings

@Test func segmentRoundtripsJSON() throws {
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1500, speaker: "Me", text: "Cześć"),
        .init(startMs: 1500, endMs: 3200, speaker: "Speaker_1", text: "Słyszę was."),
    ]
    let encoded = try MeetingSpeakerSegment.encode(segments)
    let encodedString = try #require(String(bytes: encoded, encoding: .utf8))
    let expectedString =
        #"[{"endMs":1500,"speaker":"Me","startMs":0,"text":"Cześć"},"#
        + #"{"endMs":3200,"speaker":"Speaker_1","startMs":1500,"text":"Słyszę was."}]"#
    #expect(
        encodedString
            == expectedString
    )
    let decoded = try MeetingSpeakerSegment.decode(encoded)
    #expect(decoded == segments)
}

@Test func emptySegmentsDecodeFromBracket() throws {
    let decoded = try MeetingSpeakerSegment.decode(Data("[]".utf8))
    #expect(decoded.isEmpty)
}

@Test func emptySegmentsDecodeFromEmptyData() throws {
    let decoded = try MeetingSpeakerSegment.decode(Data())
    #expect(decoded.isEmpty)
}

@Test func participantRoundtrips() throws {
    let participants: [MeetingParticipant] = [
        .init(speakerID: "Me", displayName: "Kacper"),
        .init(speakerID: "Speaker_1", displayName: "Łukasz Żółć"),
    ]
    let encoded = try MeetingParticipant.encode(participants)
    let encodedString = try #require(String(bytes: encoded, encoding: .utf8))
    #expect(
        encodedString
            == #"[{"displayName":"Kacper","speakerID":"Me"},{"displayName":"Łukasz Żółć","speakerID":"Speaker_1"}]"#
    )
    let decoded = try MeetingParticipant.decode(encoded)
    #expect(decoded == participants)
}

@Test func emptyParticipantsDecodeFromEmptyData() throws {
    let decoded = try MeetingParticipant.decode(Data())
    #expect(decoded.isEmpty)
}
