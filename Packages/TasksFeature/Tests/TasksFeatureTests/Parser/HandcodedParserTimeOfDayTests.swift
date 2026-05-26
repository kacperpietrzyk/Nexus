import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser time-of-day")
struct HandcodedParserTimeOfDayTests {
    let parser = HandcodedParser()
    let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    @Test("English 'morning' sets startAt to 09:00 today")
    func englishMorning() async {
        let result = await parser.parse(
            "call mom morning", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "call mom")
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 9, minute: 0))
        #expect(result.startAt == expected)
    }

    @Test("Polish 'wieczorem' sets startAt to 19:00 today")
    func polishWieczorem() async {
        let result = await parser.parse(
            "trening wieczorem", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 19, minute: 0))
        #expect(result.startAt == expected)
    }

    @Test("Polish 'rano' combined with 'jutro' sets dueAt tomorrow + startAt 09:00 tomorrow")
    func polishJutroRano() async {
        let result = await parser.parse(
            "budzik jutro rano", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "budzik")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-05T00:00:00Z"))
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 9, minute: 0))
        #expect(result.startAt == expected)
    }

    @Test("Polish 'po południu' (two words) sets startAt to 15:00 today")
    func polishPoPoludniu() async {
        let result = await parser.parse(
            "spotkanie po południu",
            locale: Locale(identifier: "pl"),
            now: now,
            calendar: ParserCalendar.deterministic
        )
        #expect(result.title == "spotkanie")
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 15, minute: 0))
        #expect(result.startAt == expected)
    }

    @Test("Polish 'w południe' (two words) sets startAt to 12:00 today")
    func polishWPoludnie() async {
        let result = await parser.parse(
            "lunch w południe",
            locale: Locale(identifier: "pl"),
            now: now,
            calendar: ParserCalendar.deterministic
        )
        #expect(result.title == "lunch")
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 12, minute: 0))
        #expect(result.startAt == expected)
    }

    @Test("Polish 'w nocy' (two words) sets startAt to 22:00 today")
    func polishWNocy() async {
        let result = await parser.parse(
            "praca w nocy",
            locale: Locale(identifier: "pl"),
            now: now,
            calendar: ParserCalendar.deterministic
        )
        #expect(result.title == "praca")
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 22, minute: 0))
        #expect(result.startAt == expected)
    }
}
