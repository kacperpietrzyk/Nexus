import Foundation
import NexusCore

/// `DateExtracting` conformance backing the `NexusCore` boundary protocol with
/// the existing handcoded NL date parser. Lives in `TasksFeature` (which owns
/// the parser) so feature modules that cannot import `TasksFeature` — e.g.
/// `NexusMeetings` — can still resolve free-text date hints when a host
/// composition root injects this adapter through the `DateExtracting` protocol.
///
/// Introduces **no new date logic**: it forwards to `HandcodedParser` (the
/// deterministic, offline, locale-driven parser) and surfaces its `dueAt`.
/// `deadlineAt` falls back to `dueAt` so a hint phrased as a hard deadline
/// ("by Friday") still resolves when the parser routes it to `deadlineAt`.
public struct NLParserDateExtractor: DateExtracting {
    private let parser: any NLParser
    private let calendar: Calendar?

    /// - Parameters:
    ///   - parser: The backing parser. Defaults to `HandcodedParser`, which is
    ///     fully offline and deterministic with an injected `now`/`calendar`.
    ///   - calendar: Calendar used for resolution. When `nil` (the default) the
    ///     parser's production calendar (iso8601 pinned to the user's current
    ///     time zone) is used; tests may pin a deterministic calendar.
    public init(
        parser: any NLParser = HandcodedParser(),
        calendar: Calendar? = nil
    ) {
        self.parser = parser
        self.calendar = calendar
    }

    public func date(from hint: String, now: Date, locale: Locale) async -> Date? {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let result: ParseResult
        if let calendar {
            result = await parser.parse(trimmed, locale: locale, now: now, calendar: calendar)
        } else {
            result = await parser.parse(trimmed, locale: locale, now: now)
        }
        return result.dueAt ?? result.deadlineAt
    }
}
