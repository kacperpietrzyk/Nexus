import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("HandcodedParser priority")
struct HandcodedParserPriorityTests {
    let parser = HandcodedParser()
    let now = Date()

    @Test("'!1' maps to high priority")
    func priorityOne() async {
        let result = await parser.parse(
            "ship feature !1", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "ship feature")
        #expect(result.priority == .high)
    }

    @Test("'!2' maps to medium")
    func priorityTwo() async {
        let result = await parser.parse("review !2", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.priority == .medium)
    }

    @Test("'!3' maps to low")
    func priorityThree() async {
        let result = await parser.parse(
            "nice-to-have !3", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.priority == .low)
    }

    @Test("'!4' maps to none")
    func priorityFour() async {
        let result = await parser.parse("polish !4", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.priority == TaskPriority.none)
    }

    @Test("priority token excluded from title")
    func priorityNotInTitle() async {
        let result = await parser.parse("buy milk !2", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "buy milk")
    }
}
