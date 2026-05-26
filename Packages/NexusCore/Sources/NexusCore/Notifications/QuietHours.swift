import Foundation

/// User-configured nightly quiet window. Stored as `(startHour, startMinute,
/// endHour, endMinute)` in `UserDefaults`. Notification scheduler defers
/// triggers that fall inside the window to `nextActive(after:)`.
public struct QuietHours: Codable, Equatable, Sendable {
    public let startHour: Int
    public let startMinute: Int
    public let endHour: Int
    public let endMinute: Int

    public init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    /// `true` if `date` falls inside the quiet window. Handles wrap-around
    /// (e.g., 22:00–07:00).
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        if start <= end {
            return minute >= start && minute < end
        }
        return minute >= start || minute < end
    }

    /// First instant on or after `date` that lies outside the quiet window.
    /// If `date` is already outside, returns `date` unchanged.
    public func nextActive(after date: Date, calendar: Calendar) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        let day = calendar.startOfDay(for: date)
        guard
            let candidate = calendar.date(
                bySettingHour: endHour,
                minute: endMinute,
                second: 0,
                of: day
            )
        else {
            return date
        }
        if candidate > date {
            return candidate
        }
        // Wrap-around: end is in the next day.
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? date
    }
}

/// `UserDefaults`-backed store for quiet hours. Mirrors the existing pattern
/// of `UserDefaultsConsentStore` in NexusAI: `final class` + `@unchecked
/// Sendable` because `UserDefaults` is itself thread-safe (Apple-documented)
/// but not formally annotated `Sendable`.
public final class UserDefaultsQuietHoursStore: @unchecked Sendable {
    public static let key = "com.kacperpietrzyk.Nexus.tasks.quietHours"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func load() -> QuietHours? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(QuietHours.self, from: data)
    }

    public func save(_ hours: QuietHours?) {
        if let hours, let data = try? JSONEncoder().encode(hours) {
            defaults.set(data, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}

extension UserDefaults {
    /// App Group suite shared between iPhone, Mac (no-op there) and Watch.
    /// Falls back to `.standard` so unit tests can pass an explicit suite via DI.
    public static var nexusGroup: UserDefaults {
        UserDefaults(suiteName: "group.com.kacperpietrzyk.Nexus") ?? .standard
    }
}

extension UserDefaultsQuietHoursStore {
    /// Idempotent one-shot migration from `.standard` into the App Group suite.
    /// No-op when the suite is already populated. Removes the legacy key
    /// after a successful copy.
    public static func migrate(from legacy: UserDefaults, into suite: UserDefaults) {
        guard suite.data(forKey: key) == nil else { return }
        guard let data = legacy.data(forKey: key) else { return }
        suite.set(data, forKey: key)
        legacy.removeObject(forKey: key)
    }

    /// Convenience entry point for app launch. Bridges
    /// `UserDefaults.standard → UserDefaults.nexusGroup`.
    public static func migrateFromStandardIfNeeded() {
        migrate(from: .standard, into: .nexusGroup)
    }
}
