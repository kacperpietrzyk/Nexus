import Foundation
import Testing

@testable import TasksFeature

@Suite("English corpus")
struct EnglishCorpusTests {
    @Test("each fixture parses to expected ParseResult", arguments: EnglishCorpus.fixtures)
    func eachFixture(_ fixture: ParserFixture) async {
        let parser = HandcodedParser()
        let result = await parser.parse(
            fixture.input, locale: Locale(identifier: "en"), now: EnglishCorpus.now, calendar: ParserCalendar.deterministic)
        #expect(fixture.matches(result), "EN parse failed for: \(fixture.input). Got: \(result)")
    }

    @Test("aggregate pass rate >= 90%")
    func aggregatePassRate() async {
        let parser = HandcodedParser()
        var passes = 0
        for fixture in EnglishCorpus.fixtures {
            let result = await parser.parse(
                fixture.input, locale: Locale(identifier: "en"), now: EnglishCorpus.now, calendar: ParserCalendar.deterministic)
            if fixture.matches(result) { passes += 1 }
        }
        let rate = Double(passes) / Double(EnglishCorpus.fixtures.count)
        #expect(rate >= 0.90, "English pass rate \(rate * 100)% < 90%")
    }
}
