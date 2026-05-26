import Foundation

/// Subset of RFC 5545 RRULE that Nexus supports per spec T5.
public struct RRule: Equatable, Codable, Sendable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
    }

    public enum Weekday: String, Codable, Sendable, CaseIterable {
        case monday = "MO"
        case tuesday = "TU"
        case wednesday = "WE"
        case thursday = "TH"
        case friday = "FR"
        case saturday = "SA"
        case sunday = "SU"
    }

    public var frequency: Frequency
    public var interval: Int
    public var byWeekday: [Weekday]
    public var byMonthDay: Int?
    public var until: Date?
    public var count: Int?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        byWeekday: [Weekday] = [],
        byMonthDay: Int? = nil,
        until: Date? = nil,
        count: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.byWeekday = byWeekday
        self.byMonthDay = byMonthDay
        self.until = until
        self.count = count
    }
}
