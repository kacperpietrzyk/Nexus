import Foundation

/// Contract implemented by `HandcodedParser`, `FoundationModelParser`, and
/// `CompositeNLParser`. `now` is injected so tests can pin a deterministic
/// clock; in production callers pass `Date()`. `calendar` is injected so
/// tests can pin a deterministic time zone (UTC) while production uses
/// the user's current time zone — "14:00 jutro" must resolve to local 14:00.
public protocol NLParser: Sendable {
    func parse(_ input: String, locale: Locale, now: Date, calendar: Calendar) async -> ParseResult
}

extension NLParser {
    /// Production-default overload — uses iso8601 calendar pinned to the user's
    /// current time zone. Tests should call the 4-arg form with an explicit
    /// `.gmt`-pinned calendar so corpus fixtures are deterministic regardless
    /// of where the test machine sits.
    public func parse(_ input: String, locale: Locale, now: Date) async -> ParseResult {
        await parse(input, locale: locale, now: now, calendar: ParserCalendar.production)
    }
}
