import Foundation

/// The single source of truth for how a daily note (`NoteRole.dailyNote`) is
/// identified by date. Extracted from `AgentBriefDailyNoteWriter` (NexusAgent)
/// so the agent's brief upsert and the user-facing "Today's note" flow
/// (`DailyNoteService`) agree on ONE note per day — byte-identical title,
/// day key, and tags.
///
/// Convention (pinned by `AgentBriefServiceTests.runtimeSuccessUpsertsDailyNote`):
/// - day key: `yyyy-MM-dd` of the calendar's `startOfDay`, formatted with
///   `en_US_POSIX` in the calendar's time zone (e.g. `2026-06-11`);
/// - title:   `Daily Brief <dayKey>`;
/// - tags:    `["daily", <dayKey>]`.
public enum DailyNoteConvention {
    private static let titlePrefix = "Daily Brief "

    /// `yyyy-MM-dd` for the day containing `date`, in the calendar's time zone.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        formatter(for: calendar).string(from: calendar.startOfDay(for: date))
    }

    /// The deterministic daily-note title for the day containing `date`.
    public static func title(for date: Date, calendar: Calendar = .current) -> String {
        titlePrefix + dayKey(for: date, calendar: calendar)
    }

    /// The deterministic daily-note tags for the day containing `date`.
    public static func tags(for date: Date, calendar: Calendar = .current) -> [String] {
        ["daily", dayKey(for: date, calendar: calendar)]
    }

    /// Inverse of `title(for:)`: the start-of-day `Date` encoded in a daily-note
    /// title, or `nil` when the title doesn't follow the convention. The
    /// round-trip guard rejects partial parses (e.g. trailing garbage).
    public static func date(fromTitle title: String, calendar: Calendar = .current) -> Date? {
        guard title.hasPrefix(titlePrefix) else { return nil }
        let key = String(title.dropFirst(titlePrefix.count))
        guard
            let parsed = formatter(for: calendar).date(from: key),
            dayKey(for: parsed, calendar: calendar) == key
        else { return nil }
        return calendar.startOfDay(for: parsed)
    }

    // nonisolated(unsafe) required: NSCache is a class and not marked Sendable,
    // so Swift 6 strict concurrency rejects it as static storage. Safe here
    // because NSCache documents its own internal thread-safety, and configured
    // DateFormatters are documented thread-safe for reads (since macOS 10.9 /
    // iOS 7); cached formatters are never mutated after insertion.
    private nonisolated(unsafe) static let formatterCache = NSCache<NSString, DateFormatter>()

    /// `DateFormatter` is an expensive Objective-C object; `adjacentDailyNote`
    /// calls `date(fromTitle:)` once per live daily note, so an uncached
    /// formatter would allocate O(notes) per chevron tap. Cached per calendar
    /// identity (identifier + time zone) — the only inputs `yyyy-MM-dd`
    /// formatting depends on.
    private static func formatter(for calendar: Calendar) -> DateFormatter {
        let key = "\(calendar.identifier)|\(calendar.timeZone.identifier)" as NSString
        if let cached = formatterCache.object(forKey: key) {
            return cached
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatterCache.setObject(formatter, forKey: key)
        return formatter
    }
}
