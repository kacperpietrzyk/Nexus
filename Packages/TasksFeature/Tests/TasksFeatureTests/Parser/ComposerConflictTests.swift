import Foundation
import Testing

@testable import TasksFeature

@Suite("Composer conflict resolution")
struct ComposerConflictTests {
    let parser = HandcodedParser()
    let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    @Test("explicit ISO date overrides earlier 'jutro'")
    func isoOverridesJutro() async {
        let result = await parser.parse(
            "review jutro 2026-05-15", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-15T00:00:00Z"))
    }

    @Test("'jutro' wins when it appears later than ISO")
    func laterRelativeDayWins() async {
        let result = await parser.parse(
            "review 2026-05-15 jutro", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.dueAt == ISO8601DateFormatter.fixedNoon.date(from: "2026-05-05T00:00:00Z"))
    }

    @Test("priority duplicated keeps last")
    func priorityLastWins() async {
        let result = await parser.parse("ship !2 !1", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.priority == .high)
    }

    @Test("tags accumulate without dedup at this layer")
    func tagsAccumulate() async {
        let result = await parser.parse(
            "ship #work #work", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.tags == ["work", "work"])
    }
}
