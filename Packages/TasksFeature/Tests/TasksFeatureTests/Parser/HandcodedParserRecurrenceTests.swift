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

    @Test("English 'every! day' yields completion-anchored FREQ=DAILY")
    func everyBangDay() async {
        let result = await parser.parse(
            "water plants every! day", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "water plants")
        #expect(result.recurrence == "FREQ=DAILY;ANCHOR=COMPLETION")
    }

    @Test("English 'every! monday' yields completion-anchored weekly BYDAY=MO")
    func everyBangMonday() async {
        let result = await parser.parse(
            "standup every! monday", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=WEEKLY;BYDAY=MO;ANCHOR=COMPLETION")
    }

    @Test("English 'daily!' yields completion-anchored FREQ=DAILY")
    func dailyBang() async {
        let result = await parser.parse(
            "stretch daily!", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=DAILY;ANCHOR=COMPLETION")
    }

    @Test("Polish 'co! dzień' yields completion-anchored FREQ=DAILY")
    func coBangDzien() async {
        let result = await parser.parse(
            "medytacja co! dzień", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "medytacja")
        #expect(result.recurrence == "FREQ=DAILY;ANCHOR=COMPLETION")
    }

    @Test("Polish 'codziennie!' yields completion-anchored FREQ=DAILY")
    func codziennieBang() async {
        let result = await parser.parse(
            "medytacja codziennie!", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=DAILY;ANCHOR=COMPLETION")
    }

    @Test("plain 'every day' stays due-date anchored — regression lock")
    func everyDayUnanchored() async {
        let result = await parser.parse(
            "water plants every day", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=DAILY")
    }
}
