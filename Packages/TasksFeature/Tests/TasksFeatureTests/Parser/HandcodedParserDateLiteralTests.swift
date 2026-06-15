import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser date literals")
struct HandcodedParserDateLiteralTests {
    let parser = HandcodedParser()
    // 2026-05-04 12:00 UTC for deterministic tests.
    let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    @Test("ISO date sets dueAt at midnight UTC")
    func isoDate() async {
        let result = await parser.parse(
            "ship review 2026-05-15", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "ship review")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-15T00:00:00Z"))
        #expect(result.confidence >= 0.9)
    }

    @Test("DD.MM.YYYY date sets dueAt")
    func ddmmyyyy() async {
        let result = await parser.parse(
            "buy milk 15.05.2026", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "buy milk")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-15T00:00:00Z"))
    }

    @Test("DD.MM rolls forward to next occurrence within current year")
    func ddmmRollsForward() async {
        // now = May 4. Input "10.06" → June 10 of same year.
        let result = await parser.parse("vet 10.06", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "vet")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-06-10T00:00:00Z"))
    }

    @Test("DD.MM in the past rolls to next year")
    func ddmmRollsToNextYear() async {
        // now = May 4. Input "01.03" → March 1 next year (2027).
        let result = await parser.parse("renew 01.03", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2027-03-01T00:00:00Z"))
    }

    @Test("HH:MM sets startAt offset from today midnight")
    func hhmmSetsStart() async {
        let result = await parser.parse("standup 09:30", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "standup")
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 9, minute: 30))
        #expect(result.startAt == expected)
    }

    @Test("impossible DD.MM.YYYY rejected, raw token lands in title")
    func impossibleDDMMYYYY() async {
        // 2026 is not a leap year — Feb 29 is invalid.
        let result = await parser.parse(
            "renew 29.02.2026", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == nil)
        #expect(result.title == "renew 29.02.2026")
    }

    @Test("impossible YYYY-MM-DD rejected, raw token lands in title")
    func impossibleISODate() async {
        let result = await parser.parse(
            "audit 2026-02-30", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == nil)
        #expect(result.title == "audit 2026-02-30")
    }

    @Test("partial DD.MM '29.02' in a non-leap year is rejected, not rolled to Mar 1")
    func partialFeb29NonLeapRejected() async {
        // now = May 4, 2026 (non-leap). "29.02" must NOT lenient-normalize to
        // Mar 1; the partial-date resolver should reject it entirely.
        let result = await parser.parse(
            "renew 29.02", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == nil)
        #expect(result.title == "renew 29.02")
    }

    @Test("partial DD.MM '28.02' (valid) still resolves as a control")
    func partialFeb28Valid() async {
        // now = May 4, 2026. Feb 28 is in the past this year → rolls to 2027.
        let result = await parser.parse(
            "renew 28.02", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2027-02-28T00:00:00Z"))
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let fixedNoon: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
