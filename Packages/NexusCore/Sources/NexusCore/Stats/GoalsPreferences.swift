import Foundation

/// User-configured productivity goals (T5). Persisted as a single JSON blob in
/// `UserDefaults` (the `CalendarPreferences` pattern) — deliberately NOT a
/// SwiftData entity, so no schema/migration involvement. A target of 0 means
/// "goal disabled" (hidden on the dashboard).
public struct GoalsPreferences: Codable, Equatable, Sendable {
    /// Tasks to complete per day. Default 5 (Todoist karma default). 0 = off.
    public var dailyCompletionTarget: Int
    /// Tasks to complete per week. Default 25 (Todoist karma default). 0 = off.
    public var weeklyCompletionTarget: Int

    public init(
        dailyCompletionTarget: Int = 5,
        weeklyCompletionTarget: Int = 25
    ) {
        self.dailyCompletionTarget = dailyCompletionTarget
        self.weeklyCompletionTarget = weeklyCompletionTarget
    }

    public static let `default` = GoalsPreferences()
}

/// `UserDefaults`-backed store for `GoalsPreferences`. Mirrors
/// `UserDefaultsCalendarPreferencesStore`: `final class` + `@unchecked Sendable`
/// (`UserDefaults` is thread-safe but not formally `Sendable`-annotated).
/// An unset or corrupt store returns `GoalsPreferences.default`.
public final class UserDefaultsGoalsPreferencesStore: @unchecked Sendable {
    public static let key = "com.kacperpietrzyk.Nexus.goals.preferences"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func load() -> GoalsPreferences {
        guard
            let data = defaults.data(forKey: Self.key),
            let preferences = try? JSONDecoder().decode(GoalsPreferences.self, from: data)
        else {
            return .default
        }
        return preferences
    }

    public func save(_ preferences: GoalsPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
