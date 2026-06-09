import Foundation
import Testing

@testable import NexusMeetings

@Suite struct MeetingParticipantTests {
    /// Back-compat: `participantsJSON` written before `personID` existed has no
    /// `personID` key. Synthesized `Codable` on an `Optional` uses `decodeIfPresent`,
    /// so the legacy shape must decode to `nil` — no SwiftData migration needed.
    @Test func legacyJSONWithoutPersonIDDecodesToNil() throws {
        let legacy = Data(
            #"[{"displayName":"Anna","speakerID":"Speaker_1"}]"#.utf8
        )
        let participants = try MeetingParticipant.decode(legacy)
        #expect(participants.count == 1)
        #expect(participants[0].speakerID == "Speaker_1")
        #expect(participants[0].displayName == "Anna")
        #expect(participants[0].personID == nil)
    }

    /// A participant carrying a `personID` round-trips through encode/decode intact.
    @Test func personIDRoundTripsThroughJSON() throws {
        let id = UUID()
        let original = [
            MeetingParticipant(speakerID: "Speaker_1", displayName: "Anna", personID: id)
        ]
        let decoded = try MeetingParticipant.decode(try MeetingParticipant.encode(original))
        #expect(decoded == original)
        #expect(decoded[0].personID == id)
    }

    /// The default `personID` is `nil` so all existing call sites keep compiling and
    /// `Equatable` still holds for the two-argument form.
    @Test func defaultPersonIDIsNil() {
        let participant = MeetingParticipant(speakerID: "Speaker_1", displayName: "Anna")
        #expect(participant.personID == nil)
        #expect(participant == MeetingParticipant(speakerID: "Speaker_1", displayName: "Anna"))
    }
}
