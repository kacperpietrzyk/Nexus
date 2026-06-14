import Foundation

/// Pure date arithmetic + a thin async bridge to an injected NL date parser.
/// The model never invents a date; it proposes an intent that DateMath resolves.
/// Lives in NexusCore, so it must NOT default to NLParserDateExtractor (TasksFeature, above NexusCore).
public struct DateMath: Sendable {
    public let calendar: Calendar
    private let extractor: (any DateExtracting)?

    public init(calendar: Calendar = .current, extractor: (any DateExtracting)? = nil) {
        self.calendar = calendar
        self.extractor = extractor
    }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public func addDays(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date
    }

    /// `count` consecutive start-of-day dates beginning with the day containing `from`.
    public func nextDays(_ count: Int, from: Date) -> [Date] {
        let base = startOfDay(from)
        return (0..<max(0, count)).map { addDays($0, to: base) }
    }

    public func resolve(_ hint: String, now: Date, locale: Locale) async -> Date? {
        await extractor?.date(from: hint, now: now, locale: locale)
    }
}
