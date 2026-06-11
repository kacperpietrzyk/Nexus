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
    /// M2 — how many days ahead of today the week view projects ghost preview
    /// blocks for FUTURE occurrences of recurring tasks (runtime-only, never
    /// persisted as `ScheduledBlock`s). 0 disables projection. Default 7 ≈ the
    /// current week.
    public var seriesPreviewHorizonDays: Int

    public init(
        workdayStart: DateComponents = DateComponents(hour: 9, minute: 0),
        workdayEnd: DateComponents = DateComponents(hour: 18, minute: 0),
        minBlockMinutes: Int = 15,
        maxBlockMinutes: Int = 120,
        bufferMinutes: Int = 0,
        readCalendarIDs: [String] = [],
        writeCalendarID: String? = nil,
        rolloverEnabled: Bool = true,
        seriesPreviewHorizonDays: Int = 7
    ) {
        self.workdayStart = workdayStart
        self.workdayEnd = workdayEnd
        self.minBlockMinutes = minBlockMinutes
        self.maxBlockMinutes = maxBlockMinutes
        self.bufferMinutes = bufferMinutes
        self.readCalendarIDs = readCalendarIDs
        self.writeCalendarID = writeCalendarID
        self.rolloverEnabled = rolloverEnabled
        self.seriesPreviewHorizonDays = seriesPreviewHorizonDays
    }

    /// Spec §4.4 defaults (09:00 / 18:00, 15, 120, 0, [], nil, true) + M2
    /// series-preview horizon 7.
    public static let `default` = CalendarPreferences()

    private enum CodingKeys: String, CodingKey {
        case workdayStart, workdayEnd, minBlockMinutes, maxBlockMinutes, bufferMinutes
        case readCalendarIDs, writeCalendarID, rolloverEnabled, seriesPreviewHorizonDays
    }

    /// Custom decode only: `seriesPreviewHorizonDays` was added (M2) after
    /// preference blobs already existed in UserDefaults, so a missing key must
    /// fall back to the default instead of throwing `keyNotFound` (which would
    /// silently reset the user's preferences via `load()`'s `.default`
    /// fallback). Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.workdayStart = try container.decode(DateComponents.self, forKey: .workdayStart)
        self.workdayEnd = try container.decode(DateComponents.self, forKey: .workdayEnd)
        self.minBlockMinutes = try container.decode(Int.self, forKey: .minBlockMinutes)
        self.maxBlockMinutes = try container.decode(Int.self, forKey: .maxBlockMinutes)
        self.bufferMinutes = try container.decode(Int.self, forKey: .bufferMinutes)
        self.readCalendarIDs = try container.decode([String].self, forKey: .readCalendarIDs)
        self.writeCalendarID = try container.decodeIfPresent(String.self, forKey: .writeCalendarID)
        self.rolloverEnabled = try container.decode(Bool.self, forKey: .rolloverEnabled)
        self.seriesPreviewHorizonDays =
            try container.decodeIfPresent(Int.self, forKey: .seriesPreviewHorizonDays) ?? 7
    }

    /// Filter `events` to the calendars the user has chosen to read (#6). An empty
    /// `readCalendarIDs` means "all granted calendars" (the store cannot enumerate
    /// granted calendars; the consumer resolves the implicit set), so nothing is
    /// hidden in that case. Events whose `calendarID` is unknown (`nil`) are kept
    /// even when a filter is active — hiding what cannot be classified would silently
    /// drop legitimate events.
    ///
    /// Shared by both the calendar views and the Today rail's feed so the visibility
    /// toggle is honored uniformly.
    public func visibleEvents(_ events: [CalendarEvent]) -> [CalendarEvent] {
        guard !readCalendarIDs.isEmpty else { return events }
        let allowed = Set(readCalendarIDs)
        return events.filter { event in
            guard let calendarID = event.calendarID else { return true }
            return allowed.contains(calendarID)
        }
    }
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
