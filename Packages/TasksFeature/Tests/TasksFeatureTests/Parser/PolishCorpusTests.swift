import Foundation
import Testing

@testable import TasksFeature

@Suite("Polish corpus")
struct PolishCorpusTests {
    @Test("each fixture parses to expected ParseResult", arguments: PolishCorpus.fixtures)
    func eachFixture(_ fixture: ParserFixture) async {
        let parser = HandcodedParser()
        let result = await parser.parse(
            fixture.input, locale: Locale(identifier: "pl"), now: PolishCorpus.now, calendar: ParserCalendar.deterministic)
        #expect(fixture.matches(result), "PL parse failed for: \(fixture.input). Got: \(result)")
    }

    @Test("aggregate pass rate >= 90%")
    func aggregatePassRate() async {
        let parser = HandcodedParser()
        var passes = 0
        for fixture in PolishCorpus.fixtures {
            let result = await parser.parse(
                fixture.input, locale: Locale(identifier: "pl"), now: PolishCorpus.now, calendar: ParserCalendar.deterministic)
            if fixture.matches(result) { passes += 1 }
        }
        let rate = Double(passes) / Double(PolishCorpus.fixtures.count)
        #expect(rate >= 0.90, "Polish pass rate \(rate * 100)% < 90%")
    }
}
