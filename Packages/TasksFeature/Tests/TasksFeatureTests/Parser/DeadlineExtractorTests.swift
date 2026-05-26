import Foundation
import Testing

@testable import TasksFeature

@Suite("DeadlineExtractor")
struct DeadlineExtractorTests {
    private let extractor = DeadlineExtractor()
    private let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!
    private let calendar = ParserCalendar.deterministic

    @Test("English deadline keyword strips phrase and extracts deadline")
    func englishDeadlineKeyword() {
        let result = extractor.extract(
            from: "submit report deadline tomorrow",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: calendar
        )

        #expect(result.strippedInput == "submit report")
        #expect(result.deadlineAt == date("2026-05-05T00:00:00Z"))
    }

    @Test("English by keyword preserves separate due date")
    func englishDeadlineAndDue() async {
        let parser = HandcodedParser()
        let result = await parser.parse(
            "meeting tomorrow by friday",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: calendar
        )

        #expect(result.title == "meeting")
        #expect(result.dueAt == date("2026-05-05T00:00:00Z"))
        #expect(result.deadlineAt == date("2026-05-08T00:00:00Z"))
    }

    @Test("English no later than supports date literals")
    func englishNoLaterThan() {
        let result = extractor.extract(
            from: "file taxes no later than 2026-05-15",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: calendar
        )

        #expect(result.strippedInput == "file taxes")
        #expect(result.deadlineAt == date("2026-05-15T00:00:00Z"))
    }

    @Test("English deadline keeps time when present")
    func englishDeadlineTime() {
        let result = extractor.extract(
            from: "call supplier by tomorrow 17:00",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: calendar
        )

        #expect(result.strippedInput == "call supplier")
        #expect(result.deadlineAt == date("2026-05-05T17:00:00Z"))
    }

    @Test("Polish termin keyword strips phrase and extracts deadline")
    func polishTerminKeyword() {
        let result = extractor.extract(
            from: "wysłać raport termin jutro",
            locale: Locale(identifier: "pl"),
            now: now,
            calendar: calendar
        )

        #expect(result.strippedInput == "wysłać raport")
        #expect(result.deadlineAt == date("2026-05-05T00:00:00Z"))
    }

    @Test("Polish no-later phrase supports date literals")
    func polishNoLaterThan() {
        let result = extractor.extract(
            from: "wysłać umowę najpóźniej do 15.05.2026",
            locale: Locale(identifier: "pl"),
            now: now,
            calendar: calendar
        )

        #expect(result.strippedInput == "wysłać umowę")
        #expect(result.deadlineAt == date("2026-05-15T00:00:00Z"))
    }

    @Test("Polish do dnia phrase preserves separate due date")
    func polishDeadlineAndDue() async {
        let parser = HandcodedParser()
        let result = await parser.parse(
            "spotkanie jutro do dnia 20.05",
            locale: Locale(identifier: "pl"),
            now: now,
            calendar: calendar
        )

        #expect(result.title == "spotkanie")
        #expect(result.dueAt == date("2026-05-05T00:00:00Z"))
        #expect(result.deadlineAt == date("2026-05-20T00:00:00Z"))
    }

    @Test("Polish end of week phrase sets deadline only")
    func polishEndOfWeekDeadline() async {
        let parser = HandcodedParser()
        let result = await parser.parse(
            "wysłać raport do końca tygodnia",
            locale: Locale(identifier: "pl"),
            now: now,
            calendar: calendar
        )

        #expect(result.title == "wysłać raport")
        #expect(result.dueAt == nil)
        #expect(result.deadlineAt == date("2026-05-10T00:00:00Z"))
    }

    @Test("No keyword leaves input unchanged")
    func noKeyword() {
        let result = extractor.extract(
            from: "buy milk tomorrow",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: calendar
        )

        #expect(result.strippedInput == "buy milk tomorrow")
        #expect(result.deadlineAt == nil)
    }

    private func date(_ iso: String) -> Date? {
        ISO8601DateFormatter.fixedNoon.date(from: iso)
    }
}
