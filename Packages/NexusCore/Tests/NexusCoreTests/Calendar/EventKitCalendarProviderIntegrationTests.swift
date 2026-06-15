#if canImport(EventKit) && !os(watchOS)
import CoreGraphics
import Foundation
import Testing

@testable import NexusCore

@Suite("EventKitCalendarProvider helpers")
struct EventKitCalendarProviderHelperTests {
    @Test("URL extraction scans every URL and video filter can choose a later meeting link")
    func extractsAllURLs() throws {
        let urls = EventKitCalendarProvider.urls(
            in: "Agenda: https://example.com/doc. Join: https://meet.google.com/abc-defg-hij"
        )

        #expect(urls.map(\.absoluteString) == ["https://example.com/doc", "https://meet.google.com/abc-defg-hij"])
        #expect(urls.first(where: EventKitCalendarProvider.isVideoCallURL)?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("Color hex converts through sRGB")
    func colorHexUsesSRGB() throws {
        let color = CGColor(
            srgbRed: 0.2,
            green: 0.4,
            blue: 0.6,
            alpha: 1
        )

        #expect(EventKitCalendarProvider.hexString(from: color) == "#336699")
    }

    @Test("RRule maps onto an EKRecurrenceRule (frequency, interval, weekdays, count)")
    func rruleMapsToEKRule() throws {
        let rrule = RRule(
            frequency: .weekly,
            interval: 2,
            byWeekday: [.monday, .wednesday],
            count: 5
        )
        let ekRule = try #require(EventKitCalendarProvider.ekRecurrenceRule(from: rrule))

        #expect(ekRule.frequency == .weekly)
        #expect(ekRule.interval == 2)
        #expect(ekRule.daysOfTheWeek?.map(\.dayOfTheWeek) == [.monday, .wednesday])
        #expect(ekRule.recurrenceEnd?.occurrenceCount == 5)
    }

    @Test("RRule monthly byMonthDay + until maps onto an EKRecurrenceRule")
    func rruleMonthlyMapsToEKRule() throws {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        let rrule = RRule(frequency: .monthly, interval: 1, byMonthDay: 15, until: until)
        let ekRule = try #require(EventKitCalendarProvider.ekRecurrenceRule(from: rrule))

        #expect(ekRule.frequency == .monthly)
        #expect(ekRule.daysOfTheMonth == [NSNumber(value: 15)])
        #expect(ekRule.recurrenceEnd?.endDate == until)
    }

    // MARK: - Teams meeting-ID extraction (#4a)

    @Test("Teams meeting id parsed from the join URL digits, ignoring query params")
    func teamsMeetingIDFromJoinURL() throws {
        let url = try #require(URL(string: "https://teams.microsoft.com/meet/312967000844149?p=abcDEF123"))
        let id = EventKitCalendarProvider.teamsMeetingID(notes: nil, joinURL: url, eventURL: nil)
        #expect(id == "312967000844149")
    }

    @Test("Teams meeting id parsed from a Polish label, stripping grouping spaces")
    func teamsMeetingIDFromPolishLabel() throws {
        let notes = """
            Dołącz do spotkania w aplikacji Microsoft Teams
            Identyfikator spotkania: 312 967 000 844 149
            Kod dostępu: aB1cD2
            Zadzwoń: +48 22 123 45 67
            """
        let id = EventKitCalendarProvider.teamsMeetingID(notes: notes, joinURL: nil, eventURL: nil)
        #expect(id == "312967000844149")
    }

    @Test("Teams meeting id parsed from an English label")
    func teamsMeetingIDFromEnglishLabel() throws {
        let notes = "Meeting ID: 123 456 789 012\nPasscode: zZ9"
        let id = EventKitCalendarProvider.teamsMeetingID(notes: notes, joinURL: nil, eventURL: nil)
        #expect(id == "123456789012")
    }

    @Test("Teams meeting id parsed from a join URL embedded in the notes body")
    func teamsMeetingIDFromEmbeddedURL() throws {
        let notes = "Click https://teams.microsoft.com/meet/987654321?context=x to join."
        let id = EventKitCalendarProvider.teamsMeetingID(notes: notes, joinURL: nil, eventURL: nil)
        #expect(id == "987654321")
    }

    @Test("No Teams identifier present yields nil and a bare phone number is not misread")
    func teamsMeetingIDAbsent() throws {
        let notes = "Call me at +48 600 700 800 to discuss."
        let id = EventKitCalendarProvider.teamsMeetingID(notes: notes, joinURL: nil, eventURL: nil)
        #expect(id == nil)
    }

    @Test("The join URL wins over a label when both are present")
    func teamsMeetingIDPrefersURL() throws {
        let url = try #require(URL(string: "https://teams.microsoft.com/meet/111222333?p=x"))
        let notes = "Identyfikator spotkania: 999 888 777"
        let id = EventKitCalendarProvider.teamsMeetingID(notes: notes, joinURL: url, eventURL: nil)
        #expect(id == "111222333")
    }

    @Test("completion-anchored RRule maps onto an EKRecurrenceRule with the anchor ignored")
    func anchoredRRuleMapsToEKRule() throws {
        let anchored = try RRuleParser.parse("FREQ=WEEKLY;BYDAY=MO;ANCHOR=COMPLETION")
        let ekRule = try #require(EventKitCalendarProvider.ekRecurrenceRule(from: anchored))
        #expect(ekRule.frequency == .weekly)
        #expect(ekRule.interval == 1)
        #expect(ekRule.daysOfTheWeek?.map(\.dayOfTheWeek) == [.monday])
    }
}

@Suite(
    "EventKitCalendarProvider (INTEGRATION=1)",
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1")
)
struct EventKitCalendarProviderIntegrationTests {
    @Test("Reports an authorization status")
    func reportsStatus() {
        let provider = EventKitCalendarProvider()
        let status = provider.authorizationStatus()
        let valid: [CalendarAuthorizationStatus] = [
            .notDetermined,
            .denied,
            .restricted,
            .fullAccess,
            .writeOnly,
        ]

        #expect(valid.contains(status))
    }

    @Test("eventsToday returns empty when not authorized")
    func emptyWhenUnauthorized() async throws {
        let provider = EventKitCalendarProvider()
        guard provider.authorizationStatus() != .fullAccess else { return }

        let events = try await provider.eventsToday(now: .now)
        #expect(events.isEmpty)
    }

    @Test("Nexus calendar create → event round-trip → scoped read → delete")
    func nexusCalendarRoundTrip() async throws {
        let provider = EventKitCalendarProvider()
        try await provider.requestFullAccess()
        guard provider.authorizationStatus() == .fullAccess else { return }

        let calendarID = try await provider.ensureNexusCalendar()
        // Idempotent: a second call must reuse the same calendar.
        let calendarIDAgain = try await provider.ensureNexusCalendar()
        #expect(calendarID == calendarIDAgain)

        let start = Date().addingTimeInterval(3_600)
        let end = start.addingTimeInterval(1_800)
        let draft = EventDraft(
            calendarID: calendarID,
            title: "Nexus integration round-trip",
            start: start,
            end: end
        )
        let eventID = try await provider.createEvent(draft)

        let readBack = try await provider.events(
            inCalendar: calendarID,
            start: start.addingTimeInterval(-60),
            end: end.addingTimeInterval(60)
        )
        let found = try #require(readBack.first { $0.eventID == eventID })
        #expect(found.title == "Nexus integration round-trip")
        #expect(found.calendarID == calendarID)

        try await provider.deleteEvent(id: eventID)
        let afterDelete = try await provider.events(
            inCalendar: calendarID,
            start: start.addingTimeInterval(-60),
            end: end.addingTimeInterval(60)
        )
        #expect(!afterDelete.contains { $0.eventID == eventID })
    }
}
#endif
