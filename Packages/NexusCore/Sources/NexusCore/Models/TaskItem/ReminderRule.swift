import Foundation

/// Where a relative reminder offset is measured from.
public enum ReminderAnchor: String, Codable, Equatable, Sendable {
    case due
    case deadline
}

/// How often a repeating absolute reminder re-fires (T4). Raw values are the
/// wire format inside `TaskItem.remindersData` — extend by adding cases.
public enum ReminderRepeat: String, Codable, Equatable, Sendable, CaseIterable {
    case daily
    case weekly
}

/// A single user-configurable reminder for a task. Relative rules are
/// point-in-time (recurrence spawn re-anchors them per occurrence); absolute
/// rules optionally repeat daily/weekly at their wall-clock time (T4).
/// Location-based reminders are out of scope.
public enum ReminderRule: Codable, Equatable, Sendable {
    /// Fire `offset` seconds relative to the anchor date. Negative = before.
    case relative(offset: TimeInterval, anchor: ReminderAnchor)
    /// Fire at a fixed absolute date; with `repeats` set, re-fire at that
    /// wall-clock time daily or weekly (weekday taken from the anchor date).
    case absolute(at: Date, repeats: ReminderRepeat?)

    /// One-shot absolute reminder. Keeps the pre-T4 construction spelling
    /// (`.absolute(date)`) source-compatible everywhere.
    public static func absolute(_ date: Date) -> ReminderRule {
        .absolute(at: date, repeats: nil)
    }

    private enum Kind: String, Codable { case relative, absolute }
    private enum CodingKeys: String, CodingKey {
        case kind, offset, anchor, at
        case repeats = "repeat"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .relative:
            let offset = try container.decode(TimeInterval.self, forKey: .offset)
            let anchor = try container.decode(ReminderAnchor.self, forKey: .anchor)
            self = .relative(offset: offset, anchor: anchor)
        case .absolute:
            // `repeat` is absent in pre-T4 payloads → nil (one-shot). Old
            // builds decoding a NEW payload ignore the unknown key, so a
            // repeating rule degrades to one-shot there instead of wiping
            // the whole array (the new-case failure mode we avoided).
            self = .absolute(
                at: try container.decode(Date.self, forKey: .at),
                repeats: try container.decodeIfPresent(ReminderRepeat.self, forKey: .repeats)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .relative(let offset, let anchor):
            try container.encode(Kind.relative, forKey: .kind)
            try container.encode(offset, forKey: .offset)
            try container.encode(anchor, forKey: .anchor)
        case .absolute(let at, let repeats):
            try container.encode(Kind.absolute, forKey: .kind)
            try container.encode(at, forKey: .at)
            try container.encodeIfPresent(repeats, forKey: .repeats)
        }
    }
}
