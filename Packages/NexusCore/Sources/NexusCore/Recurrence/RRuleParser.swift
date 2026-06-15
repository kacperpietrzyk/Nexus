import Foundation

/// Parses the subset of RFC 5545 RRULE that Nexus supports.
public enum RRuleParser {
    private static let supportedKeys: Set<String> = [
        "FREQ", "INTERVAL", "BYDAY", "BYMONTHDAY", "UNTIL", "COUNT", "ANCHOR",
    ]

    public static func parse(_ input: String) throws -> RRule {
        let pairs =
            input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var state = ParseState()
        for pair in pairs where !pair.isEmpty {
            try parsePair(pair, into: &state)
        }

        guard let frequency = state.frequency else {
            throw RRuleParseError.missingRequired("FREQ")
        }

        return RRule(
            frequency: frequency,
            interval: state.interval,
            byWeekday: state.byWeekday,
            byMonthDay: state.byMonthDay,
            until: state.until,
            count: state.count,
            anchor: state.anchor
        )
    }

    private static func parsePair(_ pair: String, into state: inout ParseState) throws {
        let (key, value) = try keyValue(from: pair)
        guard supportedKeys.contains(key) else {
            throw RRuleParseError.unsupportedToken(key)
        }

        switch key {
        case "FREQ":
            state.frequency = try parseFrequency(value)
        case "INTERVAL":
            state.interval = try parsePositiveInt(field: "INTERVAL", value: value)
        case "BYDAY":
            state.byWeekday = try parseWeekdays(value)
        case "BYMONTHDAY":
            state.byMonthDay = try parseMonthDay(value)
        case "UNTIL":
            state.until = try parseUntil(value)
        case "COUNT":
            state.count = try parsePositiveInt(field: "COUNT", value: value)
        case "ANCHOR":
            state.anchor = try parseAnchor(value)
        default:
            throw RRuleParseError.unsupportedToken(key)
        }
    }

    private static func keyValue(from pair: String) throws -> (key: String, value: String) {
        let parts =
            pair
            .split(separator: "=", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2 else {
            throw RRuleParseError.invalidValue(field: pair, value: "")
        }
        return (parts[0].uppercased(), parts[1])
    }

    private static func parseFrequency(_ value: String) throws -> RRule.Frequency {
        guard let parsed = RRule.Frequency(rawValue: value.uppercased()) else {
            throw RRuleParseError.invalidFrequency(value)
        }
        return parsed
    }

    private static func parsePositiveInt(field: String, value: String) throws -> Int {
        guard let parsed = Int(value), parsed >= 1 else {
            throw RRuleParseError.invalidValue(field: field, value: value)
        }
        return parsed
    }

    private static func parseWeekdays(_ value: String) throws -> [RRule.Weekday] {
        try value.split(separator: ",").map { raw in
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let day = RRule.Weekday(rawValue: code) else {
                throw RRuleParseError.invalidWeekday(code)
            }
            return day
        }
    }

    private static func parseMonthDay(_ value: String) throws -> Int {
        guard let parsed = Int(value) else {
            throw RRuleParseError.invalidValue(field: "BYMONTHDAY", value: value)
        }
        guard parsed == -1 || (1...31).contains(parsed) else {
            throw RRuleParseError.byMonthDayOutOfRange(parsed)
        }
        return parsed
    }

    private static func parseUntil(_ value: String) throws -> Date {
        guard let parsed = parseUntilDate(value) else {
            throw RRuleParseError.invalidUntilDate(value)
        }
        return parsed
    }

    private static func parseUntilDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }

    private static func parseAnchor(_ value: String) throws -> RRule.Anchor {
        guard let parsed = RRule.Anchor(rawValue: value.uppercased()) else {
            throw RRuleParseError.invalidValue(field: "ANCHOR", value: value)
        }
        return parsed
    }

    private struct ParseState {
        var frequency: RRule.Frequency?
        var interval = 1
        var byWeekday: [RRule.Weekday] = []
        var byMonthDay: Int?
        var until: Date?
        var count: Int?
        var anchor: RRule.Anchor = .dueDate
    }
}
