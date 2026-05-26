import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser tags")
struct HandcodedParserTagTests {
    let parser = HandcodedParser()
    let now = Date()

    @Test("single tag captured")
    func singleTag() async {
        let result = await parser.parse(
            "answer email #email", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "answer email")
        #expect(result.tags == ["email"])
    }

    @Test("multiple tags captured in order")
    func multipleTags() async {
        let result = await parser.parse(
            "kickoff #work #q3", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "kickoff")
        #expect(result.tags == ["work", "q3"])
    }

    @Test("tag with hierarchical slash preserved")
    func hierarchicalTag() async {
        let result = await parser.parse(
            "ship #work/projectA", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.tags == ["work/projecta"])
    }

    @Test("tag is lowercased")
    func tagLowercased() async {
        let result = await parser.parse("buy #Email", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.tags == ["email"])
    }
}
