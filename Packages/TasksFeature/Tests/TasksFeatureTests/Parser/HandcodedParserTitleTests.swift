import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser title-only")
struct HandcodedParserTitleTests {
    let parser = HandcodedParser()
    let now = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("plain text becomes title untouched")
    func plainTextTitle() async {
        let result = await parser.parse("buy milk", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "buy milk")
        #expect(result.dueAt == nil)
        #expect(result.priority == nil)
        #expect(result.tags.isEmpty)
        #expect(result.recurrence == nil)
        #expect(result.confidence == 0.0)
    }

    @Test("polish plain text becomes title untouched")
    func polishPlainTextTitle() async {
        let result = await parser.parse("kup chleb", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "kup chleb")
    }

    @Test("trims leading/trailing whitespace from title")
    func trimsWhitespace() async {
        let result = await parser.parse("  buy milk   ", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "buy milk")
    }
}
