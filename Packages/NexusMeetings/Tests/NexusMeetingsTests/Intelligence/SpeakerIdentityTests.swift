import Foundation
import Testing

@testable import NexusMeetings

@Suite("SpeakerIdentity")
struct SpeakerIdentityTests {

    // MARK: - canonicalSpeakerKey

    @Test
    func canonicalKeyNormalizesUnderscoreToSpace() {
        #expect(canonicalSpeakerKey("Participant_1") == canonicalSpeakerKey("Participant 1"))
    }

    @Test
    func canonicalKeyIsCaseInsensitive() {
        #expect(canonicalSpeakerKey("PARTICIPANT 1") == canonicalSpeakerKey("participant 1"))
    }

    @Test
    func canonicalKeyCollapsesDiacritics() {
        #expect(canonicalSpeakerKey("Józef") == canonicalSpeakerKey("Jozef"))
    }

    @Test
    func canonicalKeyCollapsesMultipleSpaces() {
        #expect(canonicalSpeakerKey("Speaker  2") == canonicalSpeakerKey("Speaker 2"))
    }

    // MARK: - renameSpeaker

    @Test
    func renamingImportedSpeakerUpdatesInPlaceNoDuplicate() {
        // Imported shape: speakerID underscored, raw segment speaker has a space.
        let participants = [MeetingParticipant(speakerID: "Participant_1", displayName: "Participant 1")]
        let updated = renameSpeaker(in: participants, rawSpeaker: "Participant 1", to: "Janek Kowalski", personID: nil)
        // no second row
        #expect(updated.count == 1)
        #expect(updated[0].displayName == "Janek Kowalski")
        // speakerID is realigned to the raw speaker token so display-lookup works.
        #expect(updated[0].speakerID == "Participant 1")
        // canonical keys stay equal (invariant)
        #expect(canonicalSpeakerKey("Participant 1") == canonicalSpeakerKey("Participant_1"))
    }

    @Test
    func renamingUnknownSpeakerAppends() {
        let participants = [MeetingParticipant(speakerID: "Speaker_1", displayName: "Speaker 1")]
        let updated = renameSpeaker(in: participants, rawSpeaker: "Speaker_2", to: "Alice", personID: nil)
        #expect(updated.count == 2)
        #expect(updated.last?.displayName == "Alice")
    }

    @Test
    func renamingNeverCreatesTwoEntriesWithSameCanonicalKey() {
        // Both entries share the canonical key — the second rename collapses them.
        let participants = [
            MeetingParticipant(speakerID: "Participant_1", displayName: "Participant 1"),
            MeetingParticipant(speakerID: "Participant 1", displayName: "Participant 1"),
        ]
        let updated = renameSpeaker(in: participants, rawSpeaker: "Participant 1", to: "Janek", personID: nil)
        #expect(updated.count == 1)
        #expect(updated[0].displayName == "Janek")
    }

    @Test
    func renamingPreservesPersonID() {
        let pid = UUID()
        let participants = [MeetingParticipant(speakerID: "Speaker_1", displayName: "Speaker 1")]
        let updated = renameSpeaker(in: participants, rawSpeaker: "Speaker 1", to: "Bob", personID: pid)
        #expect(updated[0].personID == pid)
    }
}
