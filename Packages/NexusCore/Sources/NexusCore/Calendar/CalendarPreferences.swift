import Foundation

/// User-configured calendar / scheduler settings (spec §4.4). Persisted as a
/// single JSON blob in `UserDefaults` (the `QuietHours` pattern) to sidestep
/// `DateComponents` / `[String]` / optional edge cases in per-key storage.
public struct CalendarPreferences: Codable, Equatable, Sendable {
    /// Start of the working window (hour:minute). Default 09:00.
    public var workdayStart: DateComponents
    /// End of the working window (hour:minute). Default 18:00.
    public var workdayEnd: DateComponents
    /// Minimum block length the scheduler will create.
    public var minBlockMinutes: Int
    /// Maximum block length before the scheduler splits into sub-blocks.
    public var maxBlockMinutes: Int
    /// Padding (minutes) reserved around events when computing free slots.
    public var bufferMinutes: Int
    /// Calendars read as busy obstacles. Empty = all granted calendars are read
    /// (the store cannot enumerate granted calendars; the consumer resolves
    /// "empty ⇒ all granted").
    public var readCalendarIDs: [String]
    /// Identifier of the dedicated "Nexus" write-target calendar. nil until it
    /// is created on demand (first accept or in Settings).
    public var writeCalendarID: String?
    /// Whether the daily-rollover job moves unfinished due-today/overdue tasks
    /// to the next workday.
    public var rolloverEnabled: Bool

    public init(
        workdayStart: DateComponents = DateComponents(hour: 9, minute: 0),
        workdayEnd: DateComponents = DateComponents(hour: 18, minute: 0),
        minBlockMinutes: Int = 15,
        maxBlockMinutes: Int = 120,
        bufferMinutes: Int = 0,
        readCalendarIDs: [String] = [],
        writeCalendarID: String? = nil,
        rolloverEnabled: Bool = true
    ) {
        self.workdayStart = workdayStart
        self.workdayEnd = workdayEnd
        self.minBlockMinutes = minBlockMinutes
        self.maxBlockMinutes = maxBlockMinutes
        self.bufferMinutes = bufferMinutes
        self.readCalendarIDs = readCalendarIDs
        self.writeCalendarID = writeCalendarID
        self.rolloverEnabled = rolloverEnabled
    }

    /// Spec §4.4 defaults (09:00 / 18:00, 15, 120, 0, [], nil, true).
    public static let `default` = CalendarPreferences()
}

/// `UserDefaults`-backed store for `CalendarPreferences`. Mirrors
/// `UserDefaultsQuietHoursStore`: `final class` + `@unchecked Sendable`
/// (`UserDefaults` is thread-safe but not formally `Sendable`-annotated).
/// An unset store returns `CalendarPreferences.default`.
public final class UserDefaultsCalendarPreferencesStore: @unchecked Sendable {
    public static let key = "com.kacperpietrzyk.Nexus.calendar.preferences"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func load() -> CalendarPreferences {
        guard
            let data = defaults.data(forKey: Self.key),
            let preferences = try? JSONDecoder().decode(CalendarPreferences.self, from: data)
        else {
            return .default
        }
        return preferences
    }

    public func save(_ preferences: CalendarPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
