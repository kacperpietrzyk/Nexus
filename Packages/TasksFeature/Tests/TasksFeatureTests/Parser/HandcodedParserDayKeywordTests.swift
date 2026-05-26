import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser day keywords")
struct HandcodedParserDayKeywordTests {
    let parser = HandcodedParser()
    // 2026-05-04 is a Monday in UTC.
    let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    @Test("Polish 'jutro' resolves to next day")
    func polishJutro() async {
        let result = await parser.parse("oddzwoń jutro", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "oddzwoń")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-05T00:00:00Z"))
        #expect(result.confidence >= 0.85)
    }

    @Test("English 'tomorrow' resolves to next day")
    func englishTomorrow() async {
        let result = await parser.parse(
            "call mom tomorrow", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "call mom")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-05T00:00:00Z"))
    }

    @Test("Polish 'pojutrze' resolves to +2 days")
    func polishPojutrze() async {
        let result = await parser.parse(
            "review pojutrze", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-06T00:00:00Z"))
    }

    @Test("English weekday rolls forward to next occurrence")
    func englishWeekday() async {
        // Monday 2026-05-04 → "friday" → 2026-05-08
        let result = await parser.parse(
            "ship review friday", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "ship review")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-08T00:00:00Z"))
    }

    @Test("Polish 'wtorek' rolls forward")
    func polishWtorek() async {
        // Monday 2026-05-04 → "wtorek" (Tuesday) → 2026-05-05
        let result = await parser.parse(
            "zadanie wtorek", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-05T00:00:00Z"))
    }

    @Test("Same-day keyword skips to next week")
    func sameDayWeekday() async {
        // Monday 2026-05-04 → "monday" → 2026-05-11 (next Monday, not today)
        let result = await parser.parse("retro monday", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-11T00:00:00Z"))
    }
}
