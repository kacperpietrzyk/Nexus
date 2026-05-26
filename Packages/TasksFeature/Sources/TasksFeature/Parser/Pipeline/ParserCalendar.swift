import Foundation

/// Calendars used by the parser pipeline. Production code constructs new
/// `ParserCalendar.production` (iso8601 + user's current time zone) on every
/// parse so an external time-zone change is picked up; tests pin
/// `ParserCalendar.deterministic` (iso8601 + UTC) so corpus fixtures encode
/// wall-clock UTC and stay green regardless of where the test machine sits.
internal enum ParserCalendar {
    /// `iso8601` calendar pinned to `TimeZone.current`. Recomputed every access
    /// so a TZ change at runtime is reflected in the next parse call.
    static var production: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    /// `iso8601` calendar pinned to `.gmt`. Used by parser corpus tests.
    static var deterministic: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        return calendar
    }
}
