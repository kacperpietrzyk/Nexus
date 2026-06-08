import Foundation

/// Resolves a free-text date hint (e.g. "by Friday", "do piątku") into a
/// concrete `Date`, or `nil` when the hint carries no resolvable date.
///
/// This is a pure boundary protocol owned by `NexusCore` so feature modules
/// that cannot import one another (e.g. `NexusMeetings` cannot import
/// `TasksFeature`) can still reuse the single canonical date parser via
/// dependency injection at an `Apps`/host composition root.
///
/// Implementations MUST NOT introduce new date logic — they adapt an existing
/// parser. `now` is injected so callers can pin a deterministic clock (the
/// meeting's `startedAt` in production; a fixed instant in tests). `locale`
/// selects the phrase table so both English and Polish hints resolve.
public protocol DateExtracting: Sendable {
    /// - Parameters:
    ///   - hint: Free-text date fragment such as "by Friday" or "do piątku".
    ///   - now: The reference instant relative to which relative phrases
    ///     ("Friday", "tomorrow") resolve.
    ///   - locale: Locale selecting the phrase table for parsing.
    /// - Returns: The resolved due date, or `nil` when the hint resolves to no date.
    func date(from hint: String, now: Date, locale: Locale) async -> Date?
}
