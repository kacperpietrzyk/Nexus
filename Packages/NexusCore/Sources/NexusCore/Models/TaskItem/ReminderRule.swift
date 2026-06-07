import Foundation

/// Where a relative reminder offset is measured from.
public enum ReminderAnchor: String, Codable, Equatable, Sendable {
    case due
    case deadline
}

/// A single user-configurable reminder for a task. Point-in-time only —
/// recurring and location-based reminders are out of scope.
public enum ReminderRule: Codable, Equatable, Sendable {
    /// Fire `offset` seconds relative to the anchor date. Negative = before.
    case relative(offset: TimeInterval, anchor: ReminderAnchor)
    /// Fire at a fixed absolute date.
    case absolute(Date)

    private enum Kind: String, Codable { case relative, absolute }
    private enum CodingKeys: String, CodingKey { case kind, offset, anchor, at }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .relative:
            let offset = try container.decode(TimeInterval.self, forKey: .offset)
            let anchor = try container.decode(ReminderAnchor.self, forKey: .anchor)
            self = .relative(offset: offset, anchor: anchor)
        case .absolute:
            self = .absolute(try container.decode(Date.self, forKey: .at))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .relative(let offset, let anchor):
            try container.encode(Kind.relative, forKey: .kind)
            try container.encode(offset, forKey: .offset)
            try container.encode(anchor, forKey: .anchor)
        case .absolute(let at):
            try container.encode(Kind.absolute, forKey: .kind)
            try container.encode(at, forKey: .at)
        }
    }
}
