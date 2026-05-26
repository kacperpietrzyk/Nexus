import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser recurrence")
struct HandcodedParserRecurrenceTests {
    let parser = HandcodedParser()
    let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    @Test("Polish 'co poniedziałek' yields weekly RRULE with BYDAY=MO")
    func coPoniedzialek() async {
        let result = await parser.parse(
            "planowanie co poniedziałek", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "planowanie")
        #expect(result.recurrence == "FREQ=WEEKLY;BYDAY=MO")
    }

    @Test("English 'every monday' yields weekly RRULE with BYDAY=MO")
    func everyMonday() async {
        let result = await parser.parse(
            "standup every monday", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=WEEKLY;BYDAY=MO")
    }

    @Test("English 'daily' yields FREQ=DAILY")
    func englishDaily() async {
        let result = await parser.parse(
            "water plants daily", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=DAILY")
    }

    @Test("Polish 'co dzień' yields FREQ=DAILY")
    func coDzien() async {
        let result = await parser.parse(
            "medytacja co dzień", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=DAILY")
    }

    @Test("recurrence with time-of-day yields recurrence + startAt")
    func recurrenceWithTime() async {
        let result = await parser.parse(
            "standup co poniedziałek 09:00", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=WEEKLY;BYDAY=MO")
        #expect(result.startAt != nil)
    }
}
