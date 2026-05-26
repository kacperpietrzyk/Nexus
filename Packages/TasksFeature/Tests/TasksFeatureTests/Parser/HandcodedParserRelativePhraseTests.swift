import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser relative phrases")
struct HandcodedParserRelativePhraseTests {
    let parser = HandcodedParser()
    let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    @Test("Polish 'za 3 dni' shifts dueAt by 3 days")
    func polishZa3Dni() async {
        let result = await parser.parse(
            "oddzwoń za 3 dni", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "oddzwoń")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-07T00:00:00Z"))
    }

    @Test("English 'in 5 days' shifts dueAt by 5 days")
    func englishIn5Days() async {
        let result = await parser.parse(
            "review in 5 days", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "review")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-09T00:00:00Z"))
    }

    @Test("Polish 'za tydzień' = +7 days")
    func polishZaTydzien() async {
        let result = await parser.parse(
            "planowanie za tydzień", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-11T00:00:00Z"))
    }

    @Test("English 'in 2 weeks' = +14 days")
    func englishIn2Weeks() async {
        let result = await parser.parse(
            "retro in 2 weeks", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-18T00:00:00Z"))
    }
}
