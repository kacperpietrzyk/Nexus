import Foundation
import NexusCore

/// Individual lexeme produced by `Tokenizer` and consumed by `Resolver`.
/// `confidence` lets later stages decide whether to trust the parse.
internal enum Token: Sendable, Equatable {
    case dateLiteral(String, confidence: Float)
    case dayKeyword(RRule.Weekday, confidence: Float)
    case relativeDay(offset: Int, confidence: Float)
    case timeOfDay(secondsIntoDay: TimeInterval, confidence: Float)
    case relativePhrase(amount: Int, unitDays: Int, confidence: Float)
    case priority(TaskPriority, confidence: Float)
    case tag(String, confidence: Float)
    case recurrence(rrule: String, confidence: Float)
    case residual(String)
}

extension Token {
    /// Confidence floor used by `Composer` when picking between competing
    /// tokens for the same field.
    var confidence: Float {
        switch self {
        case .dateLiteral(_, let c),
            .dayKeyword(_, let c),
            .relativeDay(_, let c),
            .timeOfDay(_, let c),
            .relativePhrase(_, _, let c),
            .priority(_, let c),
            .tag(_, let c),
            .recurrence(_, let c):
            return c
        case .residual:
            return 0.0
        }
    }
}
