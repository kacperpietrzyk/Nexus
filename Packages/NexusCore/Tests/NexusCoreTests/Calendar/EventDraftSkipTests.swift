import Foundation
import Testing

@testable import NexusCore

/// FIX C (#7): a nil `EventDraft.calendarID` means "no system-calendar event" —
/// the write surface skips the save and returns the `skippedEventID` sentinel
/// instead of throwing. Exercised through `MockCalendarWriter`, which mirrors the
/// real provider's contract (the real provider's skip happens before any EventKit
/// access, so the behavior is identical).
@Suite("EventDraft nil-calendar skip")
struct EventDraftSkipTests {
    private func draft(calendarID: String?) -> EventDraft {
        let start = Date(timeIntervalSince1970: 2_000)
        return EventDraft(
            calendarID: calendarID,
            title: "Standup",
            start: start,
            end: start.addingTimeInterval(1_800)
        )
    }

    @Test("createEvent with nil calendar returns the skip sentinel and writes nothing")
    func nilCalendarSkipsCreate() async throws {
        let writer = MockCalendarWriter()
        let id = try await writer.createEvent(draft(calendarID: nil))
        #expect(id == MockCalendarWriter.skippedEventID)

        // Nothing was persisted: a follow-up snapshot lookup finds no event.
        let snapshot = try await writer.eventSnapshot(id: id)
        #expect(snapshot == nil)
    }

    @Test("createEvent with an explicit calendar still writes a real event")
    func explicitCalendarWritesEvent() async throws {
        let writer = MockCalendarWriter()
        let id = try await writer.createEvent(draft(calendarID: "personal"))
        #expect(id != MockCalendarWriter.skippedEventID)

        let snapshot = try await writer.eventSnapshot(id: id)
        #expect(snapshot?.calendarID == "personal")
        #expect(snapshot?.title == "Standup")
    }
}
