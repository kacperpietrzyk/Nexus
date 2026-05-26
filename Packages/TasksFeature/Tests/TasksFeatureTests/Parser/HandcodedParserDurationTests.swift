import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser durations")
struct HandcodedParserDurationTests {
    private let parser = HandcodedParser()
    private let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    @Test("Polish bare duration attaches endAt after startAt")
    func polishBareDurationSetsEndAt() async {
        let result = await parser.parse(
            "spotkanie 14:00 1h", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "spotkanie")
        #expect(result.startAt == date(hour: 14, minute: 0))
        #expect(result.endAt == date(hour: 15, minute: 0))
    }

    @Test("English for-prefixed minutes attach endAt after startAt")
    func englishForMinutesSetEndAt() async {
        let result = await parser.parse(
            "meeting 14:00 for 30 minutes", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "meeting")
        #expect(result.startAt == date(hour: 14, minute: 0))
        #expect(result.endAt == date(hour: 14, minute: 30))
    }

    @Test("Polish until-time duration attaches endAt and strips residual preposition")
    func polishUntilTimeSetsEndAt() async {
        let result = await parser.parse(
            "spotkanie 14:00 do 16:00", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "spotkanie")
        #expect(result.startAt == date(hour: 14, minute: 0))
        #expect(result.endAt == date(hour: 16, minute: 0))
    }

    @Test("English compound duration attaches ninety-minute endAt")
    func englishCompoundDurationSetsEndAt() async {
        let result = await parser.parse(
            "meeting 9:00 1 hour and 30 minutes",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.title == "meeting")
        #expect(result.startAt == date(hour: 9, minute: 0))
        #expect(result.endAt == date(hour: 10, minute: 30))
    }

    @Test("Duration phrase is stripped from composed title")
    func titleStripsDurationPhrase() async {
        let result = await parser.parse(
            "planning 14:00 1h", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "planning")
        #expect(result.endAt == date(hour: 15, minute: 0))
    }

    @Test("Duration without startAt leaves endAt nil")
    func durationWithoutStartAtLeavesEndAtNil() async {
        let result = await parser.parse(
            "meeting for 30 minutes", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.startAt == nil)
        #expect(result.endAt == nil)
    }

    @Test("English endpoint-only until phrase does not become startAt")
    func englishEndpointOnlyUntilDoesNotBecomeStartAt() async {
        let result = await parser.parse(
            "meeting until 16:00", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "meeting")
        #expect(result.startAt == nil)
        #expect(result.endAt == nil)
    }

    @Test("Bare endpoint-only until phrase does not become startAt")
    func bareEndpointOnlyUntilDoesNotBecomeStartAt() async {
        let result = await parser.parse("until 16:00", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title.isEmpty)
        #expect(result.startAt == nil)
        #expect(result.endAt == nil)
    }

    @Test("Polish dated endpoint-only do phrase does not become startAt")
    func polishDatedEndpointOnlyDoDoesNotBecomeStartAt() async {
        let result = await parser.parse(
            "spotkanie jutro do 16:00", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "spotkanie")
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-05T00:00:00Z"))
        #expect(result.startAt == nil)
        #expect(result.endAt == nil)
    }

    @Test("No duration preserves title and leaves endAt nil")
    func noDurationPreservesTitleAndEndAtNil() async {
        let result = await parser.parse(
            "meeting 14:00 prep", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "meeting prep")
        #expect(result.startAt == date(hour: 14, minute: 0))
        #expect(result.endAt == nil)
    }

    @Test("Polish fractional bare-hour duration attaches endAt")
    func polishFractionalDurationSetsEndAt() async {
        let result = await parser.parse(
            "spotkanie 14:00 1.5h", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "spotkanie")
        #expect(result.endAt == date(hour: 15, minute: 30))
    }

    @Test("English spelled duration attaches endAt")
    func englishSpelledDurationSetsEndAt() async {
        let result = await parser.parse(
            "meeting 14:00 two hours", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "meeting")
        #expect(result.endAt == date(hour: 16, minute: 0))
    }

    @Test("Title preserves words around duration phrase")
    func titlePreservesWordsAroundDuration() async {
        let result = await parser.parse(
            "meeting prep 14:00 for 30 minutes with Anna",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.title == "meeting prep with Anna")
        #expect(result.endAt == date(hour: 14, minute: 30))
    }

    @Test("Polish title preserves earlier do preposition when stripping until duration")
    func polishTitlePreservesEarlierDoPreposition() async {
        let result = await parser.parse(
            "zadzwonić do mamy 14:00 do 16:00",
            locale: Locale(identifier: "pl"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.title == "zadzwonić do mamy")
        #expect(result.endAt == date(hour: 16, minute: 0))
    }

    @Test("English for prefix is stripped with duration phrase")
    func stripsForPrefixWithDurationPhrase() async {
        let result = await parser.parse(
            "focus 14:00 for 1 hour", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "focus")
        #expect(result.endAt == date(hour: 15, minute: 0))
    }

    private func date(hour: Int, minute: Int) -> Date? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: hour, minute: minute))
    }
}
