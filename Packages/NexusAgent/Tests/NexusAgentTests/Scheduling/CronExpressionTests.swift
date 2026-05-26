import Foundation
import Testing

@testable import NexusAgent

@Test func cronParsesDailyEightAM() throws {
    let expr = try CronExpression("0 8 * * *")
    let base = ISO8601DateFormatter().date(from: "2026-05-13T07:00:00Z")!
    let next = expr.next(after: base, calendar: .init(identifier: .gregorian))
    let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: next!)
    #expect(components.hour == 8)
    #expect(components.minute == 0)
}

@Test func cronParsesEveryHalfHour() throws {
    let expr = try CronExpression("*/30 * * * *")
    let base = ISO8601DateFormatter().date(from: "2026-05-13T10:14:00Z")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let next = expr.next(after: base, calendar: calendar)
    let components = calendar.dateComponents([.hour, .minute], from: next!)
    #expect(components.hour == 10)
    #expect(components.minute == 30)
}

@Test func cronRejectsInvalidExpression() {
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("bogus")
    }
}

@Test func cronRejectsZeroStep() {
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("*/0 * * * *")
    }
}

@Test func cronRejectsNegativeStep() {
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("*/-1 * * * *")
    }
}

@Test func cronRejectsMalformedLists() {
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression(", * * * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("1, * * * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("1,,2 * * * *")
    }
}

@Test func cronRejectsMalformedRanges() {
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("1--2 * * * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("1-2- * * * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("-1-2 * * * *")
    }
}

@Test func cronRejectsEmptySlashComponents() {
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("*/ * * * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("/5 * * * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("5/ * * * *")
    }
}

@Test func cronDomDowRestrictedUsesOrSemantics() throws {
    let expr = try CronExpression("0 8 15 * 1")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let mondayNotFifteenth = ISO8601DateFormatter().date(from: "2026-05-11T08:00:00Z")!
    let fifteenthNotMonday = ISO8601DateFormatter().date(from: "2026-05-15T08:00:00Z")!
    let neither = ISO8601DateFormatter().date(from: "2026-05-12T08:00:00Z")!

    #expect(expr.matches(mondayNotFifteenth, calendar: calendar))
    #expect(expr.matches(fifteenthNotMonday, calendar: calendar))
    #expect(!expr.matches(neither, calendar: calendar))
}

@Test func cronDomDowWildcardPreservesRestrictedField() throws {
    let dayRestricted = try CronExpression("0 8 15 * *")
    let weekdayRestricted = try CronExpression("0 8 * * 1")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let mondayNotFifteenth = ISO8601DateFormatter().date(from: "2026-05-11T08:00:00Z")!
    let fifteenthNotMonday = ISO8601DateFormatter().date(from: "2026-05-15T08:00:00Z")!
    let tuesday = ISO8601DateFormatter().date(from: "2026-05-12T08:00:00Z")!

    #expect(!dayRestricted.matches(mondayNotFifteenth, calendar: calendar))
    #expect(dayRestricted.matches(fifteenthNotMonday, calendar: calendar))
    #expect(weekdayRestricted.matches(mondayNotFifteenth, calendar: calendar))
    #expect(!weekdayRestricted.matches(tuesday, calendar: calendar))
}

@Test func cronDomStepWildcardPreservesRestrictedWeekday() throws {
    let expr = try CronExpression("0 8 */1 * 1")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let monday = ISO8601DateFormatter().date(from: "2026-05-11T08:00:00Z")!
    let tuesday = ISO8601DateFormatter().date(from: "2026-05-12T08:00:00Z")!

    #expect(expr.matches(monday, calendar: calendar))
    #expect(!expr.matches(tuesday, calendar: calendar))
}

@Test func cronDowStepWildcardPreservesRestrictedDay() throws {
    let expr = try CronExpression("0 8 15 * */1")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let fifteenth = ISO8601DateFormatter().date(from: "2026-05-15T08:00:00Z")!
    let sixteenth = ISO8601DateFormatter().date(from: "2026-05-16T08:00:00Z")!

    #expect(expr.matches(fifteenth, calendar: calendar))
    #expect(!expr.matches(sixteenth, calendar: calendar))
}

@Test func cronAcceptsWhitespaceSeparators() throws {
    let expr = try CronExpression("0\t8  *\t*\t*")
    #expect(expr.hour == [8])
    #expect(expr.minute == [0])
}

@Test func cronNextNormalizesToFullMinute() throws {
    let expr = try CronExpression("0 8 * * *")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = ISO8601DateFormatter().date(from: "2026-05-13T07:59:42Z")!
    let next = try #require(expr.next(after: base, calendar: calendar))
    let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: next)

    #expect(components.hour == 8)
    #expect(components.minute == 0)
    #expect(components.second == 0)
    #expect(components.nanosecond == 0)
}

@Test func cronNextFindsLeapDayAcrossFourYearCycle() throws {
    let expr = try CronExpression("0 0 29 2 *")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let base = ISO8601DateFormatter().date(from: "2025-03-01T00:00:00Z")!
    let next = try #require(expr.next(after: base, calendar: calendar))
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: next)

    #expect(components.year == 2028)
    #expect(components.month == 2)
    #expect(components.day == 29)
    #expect(components.hour == 0)
    #expect(components.minute == 0)
    #expect(components.second == 0)
}

@Test func cronParsesRangeStep() throws {
    let expr = try CronExpression("10-20/5 * * * *")
    #expect(expr.minute == Set([10, 15, 20]))
}

@Test func cronRejectsOutOfRangeFields() {
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("60 * * * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("* 24 * * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("* * 32 * *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("* * * 13 *")
    }
    #expect(throws: CronExpressionError.self) {
        _ = try CronExpression("* * * * 7")
    }
}
