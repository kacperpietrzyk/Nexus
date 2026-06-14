import Foundation

/// Pure capacity model: how many productive minutes a day holds.
/// v1 default derives from the calendar workday window; a user setting can override later (spec §10.3).
public struct CapacityModel: Sendable, Equatable {
    public let dailyCapacityMinutes: Int

    public init(dailyCapacityMinutes: Int) {
        self.dailyCapacityMinutes = max(0, dailyCapacityMinutes)
    }

    public static func fromPreferences(_ prefs: CalendarPreferences) -> CapacityModel {
        let startMin = (prefs.workdayStart.hour ?? 9) * 60 + (prefs.workdayStart.minute ?? 0)
        let endMin = (prefs.workdayEnd.hour ?? 18) * 60 + (prefs.workdayEnd.minute ?? 0)
        return CapacityModel(dailyCapacityMinutes: (endMin - startMin) - prefs.bufferMinutes)
    }
}
