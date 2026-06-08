import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("NLParserDateExtractor")
struct NLParserDateExtractorTests {
    // Monday 2026-05-04 noon UTC — same deterministic anchor the parser corpus uses.
    private let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!
    private let calendar = ParserCalendar.deterministic

    private func extractor() -> NLParserDateExtractor {
        NLParserDateExtractor(parser: HandcodedParser(), calendar: calendar)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter.fixedNoon.date(from: iso)!
    }

    @Test("English 'by Friday' resolves to the upcoming Friday")
    func englishByFriday() async {
        let resolved = await extractor().date(
            from: "by Friday",
            now: now,
            locale: Locale(identifier: "en")
        )
        #expect(resolved == date("2026-05-08T00:00:00Z"))
    }

    // The spec illustrates the Polish case as "do piątku". The existing parser
    // recognizes the nominative day keyword "piątek" (not the genitive "piątku")
    // and the deadline phrase "do końca tygodnia"; we reuse those real phrases
    // rather than adding new date logic (I6). Both must resolve to a date.
    @Test("Polish 'piątek' resolves to the upcoming Friday")
    func polishPiatek() async {
        let resolved = await extractor().date(
            from: "piątek",
            now: now,
            locale: Locale(identifier: "pl")
        )
        #expect(resolved == date("2026-05-08T00:00:00Z"))
    }

    @Test("Polish deadline 'do końca tygodnia' resolves to a date")
    func polishDoKoncaTygodnia() async {
        let resolved = await extractor().date(
            from: "do końca tygodnia",
            now: now,
            locale: Locale(identifier: "pl")
        )
        #expect(resolved != nil)
    }

    // Characterization (not aspiration): the spec §12 literal example "do piątku"
    // does NOT resolve with the existing parser — the day table only knows the
    // nominative "piątek" (not the genitive "piątku"), and bare "do" is not a
    // recognized Polish deadline marker ("do końca"/"do dnia"/"najpóźniej do" are).
    // Resolving it would require NEW date logic, which is out of scope (I6).
    // Degrades gracefully: an unresolved hint yields a task without `dueAt`.
    @Test("Polish 'do piątku' is unresolved by the existing parser (documented gap)")
    func polishDoPiatkuUnresolved() async {
        let resolved = await extractor().date(
            from: "do piątku",
            now: now,
            locale: Locale(identifier: "pl")
        )
        #expect(resolved == nil)
    }

    @Test("Unresolvable hint returns nil")
    func unresolvableHintReturnsNil() async {
        let resolved = await extractor().date(
            from: "soonish whenever",
            now: now,
            locale: Locale(identifier: "en")
        )
        #expect(resolved == nil)
    }

    @Test("Blank hint returns nil without invoking the parser")
    func blankHintReturnsNil() async {
        let resolved = await extractor().date(
            from: "   ",
            now: now,
            locale: Locale(identifier: "en")
        )
        #expect(resolved == nil)
    }
}
