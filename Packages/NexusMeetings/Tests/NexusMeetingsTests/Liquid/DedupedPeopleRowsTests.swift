#if os(macOS)
import Foundation
import NexusCore
import Testing

@testable import NexusMeetings

@Suite("dedupedPeopleRows")
struct DedupedPeopleRowsTests {

    // MARK: - Helpers

    private static func attendee(
        id: String, name: String, personID: UUID? = nil
    ) -> LiquidMeetingsModel.Attendee {
        LiquidMeetingsModel.Attendee(id: id, name: name, personID: personID)
    }

    private static func linkedPerson(
        title: String, targetID: UUID = UUID()
    ) -> LiquidMeetingsModel.LinkedItem {
        LiquidMeetingsModel.LinkedItem(
            id: UUID(), kind: .person, targetID: targetID, title: title, isBacklink: false)
    }

    // MARK: - Placeholder speakers + junk Person links → 3 unassigned rows

    @Test
    func placeholderSpeakersWithJunkPersonLinksProduceUnassignedRows() {
        let attendees = [
            Self.attendee(id: "Participant_1", name: "Participant 1"),
            Self.attendee(id: "Participant_2", name: "Participant 2"),
            Self.attendee(id: "Participant_3", name: "Participant 3"),
        ]
        let linkedPersons = [
            Self.linkedPerson(title: "Participant 1"),
            Self.linkedPerson(title: "Participant 2"),
            Self.linkedPerson(title: "Participant 3"),
        ]

        let rows = dedupedPeopleRows(attendees: attendees, linkedPersons: linkedPersons)

        #expect(rows.count == 3, "Expected exactly 3 rows, got \(rows.count)")
        for row in rows {
            #expect(row.targetID == nil, "Placeholder row should not be assigned: \(row.name)")
            #expect(row.rawSpeaker != nil, "Placeholder row should expose Assign button: \(row.name)")
        }
    }

    // MARK: - Real-named link → 1 assigned row

    @Test
    func realNamedLinkedPersonProducesAssignedRow() {
        let personID = UUID()
        let attendees = [Self.attendee(id: "Speaker_1", name: "Alice Smith")]
        let linkedPersons = [Self.linkedPerson(title: "Alice Smith", targetID: personID)]

        let rows = dedupedPeopleRows(attendees: attendees, linkedPersons: linkedPersons)

        #expect(rows.count == 1)
        #expect(rows[0].targetID == personID)
        #expect(rows[0].rawSpeaker == nil)
        #expect(rows[0].name == "Alice Smith")
    }

    // MARK: - No duplicates: attendee already has personID

    @Test
    func attendeeWithPersonIDIsAssigned() {
        let personID = UUID()
        let attendees = [Self.attendee(id: "Speaker_1", name: "Bob Jones", personID: personID)]

        let rows = dedupedPeopleRows(attendees: attendees, linkedPersons: [])

        #expect(rows.count == 1)
        #expect(rows[0].targetID == personID)
        #expect(rows[0].rawSpeaker == nil)
    }

    // MARK: - Mixed: one placeholder, one real-named

    @Test
    func mixedPlaceholderAndRealNamedProducesCorrectAssignment() {
        let realPersonID = UUID()
        let attendees = [
            Self.attendee(id: "Participant_1", name: "Participant 1"),
            Self.attendee(id: "Speaker_2", name: "Carol Tan"),
        ]
        let linkedPersons = [
            Self.linkedPerson(title: "Participant 1"),
            Self.linkedPerson(title: "Carol Tan", targetID: realPersonID),
        ]

        let rows = dedupedPeopleRows(attendees: attendees, linkedPersons: linkedPersons)

        #expect(rows.count == 2)
        let participant = rows.first { $0.name == "Participant 1" }
        let carol = rows.first { $0.name == "Carol Tan" }
        #expect(participant?.targetID == nil, "Placeholder should be unassigned")
        #expect(participant?.rawSpeaker != nil, "Placeholder should have Assign button")
        #expect(carol?.targetID == realPersonID, "Real name should be assigned")
        #expect(carol?.rawSpeaker == nil)
    }

    // MARK: - Graph-only linked persons (no matching attendee)

    @Test
    func graphOnlyPersonAppearsAsRow() {
        let personID = UUID()
        let linkedPersons = [Self.linkedPerson(title: "Diana Prince", targetID: personID)]

        let rows = dedupedPeopleRows(attendees: [], linkedPersons: linkedPersons)

        #expect(rows.count == 1)
        #expect(rows[0].targetID == personID)
        #expect(rows[0].rawSpeaker == nil)
    }
}
#endif
