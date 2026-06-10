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

    /// Non-standard extension (T1 completion-based recurrence): which date the
    /// next occurrence advances from. `.dueDate` is RFC behavior and the
    /// default; `.completion` is Todoist "every!" — advance from the date the
    /// task was completed. Serialized as the `ANCHOR=` RRULE token; an absent
    /// token means `.dueDate`, so every pre-existing stored rule is unchanged.
    public enum Anchor: String, Codable, Sendable, CaseIterable {
        case dueDate = "DUE"
        case completion = "COMPLETION"
    }

    public var frequency: Frequency
    public var interval: Int
    public var byWeekday: [Weekday]
    public var byMonthDay: Int?
    public var until: Date?
    public var count: Int?
    public var anchor: Anchor

    public init(
        frequency: Frequency,
        interval: Int = 1,
        byWeekday: [Weekday] = [],
        byMonthDay: Int? = nil,
        until: Date? = nil,
        count: Int? = nil,
        anchor: Anchor = .dueDate
    ) {
        self.frequency = frequency
        self.interval = interval
        self.byWeekday = byWeekday
        self.byMonthDay = byMonthDay
        self.until = until
        self.count = count
        self.anchor = anchor
    }

    private enum CodingKeys: String, CodingKey {
        case frequency, interval, byWeekday, byMonthDay, until, count, anchor
    }

    /// Custom decode only: `anchor` was added after `RRule` payloads already
    /// existed in the wild (agent tool args round-trip through Codable), so a
    /// missing key must fall back to `.dueDate` instead of throwing
    /// `keyNotFound`. Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.frequency = try container.decode(Frequency.self, forKey: .frequency)
        self.interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1
        self.byWeekday = try container.decodeIfPresent([Weekday].self, forKey: .byWeekday) ?? []
        self.byMonthDay = try container.decodeIfPresent(Int.self, forKey: .byMonthDay)
        self.until = try container.decodeIfPresent(Date.self, forKey: .until)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
        self.anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor) ?? .dueDate
    }
}
