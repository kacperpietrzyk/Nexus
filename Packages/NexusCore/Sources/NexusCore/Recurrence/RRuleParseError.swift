import Foundation

/// Errors thrown by `RRuleParser`. Each case carries the offending fragment so UI
/// can highlight invalid recurrence chips later.
public enum RRuleParseError: Error, Equatable, Sendable {
    case unsupportedToken(String)
    case invalidFrequency(String)
    case invalidValue(field: String, value: String)
    case missingRequired(String)
    case byMonthDayOutOfRange(Int)
    case invalidWeekday(String)
    case invalidUntilDate(String)
}
