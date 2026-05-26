import Foundation

public enum CronExpressionError: Error, Equatable {
    case wrongFieldCount(Int)
    case invalidField(String)
}

public struct CronExpression: Sendable, Equatable {
    public let minute: Set<Int>
    public let hour: Set<Int>
    public let day: Set<Int>
    public let month: Set<Int>
    public let weekday: Set<Int>
    private let dayIsWildcard: Bool
    private let weekdayIsWildcard: Bool

    public init(_ expression: String) throws {
        let fields = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5 else {
            throw CronExpressionError.wrongFieldCount(fields.count)
        }
        self.minute = try Self.parse(fields[0], range: 0...59)
        self.hour = try Self.parse(fields[1], range: 0...23)
        self.day = try Self.parse(fields[2], range: 1...31)
        self.month = try Self.parse(fields[3], range: 1...12)
        self.weekday = try Self.parse(fields[4], range: 0...6)
        self.dayIsWildcard = fields[2].hasPrefix("*")
        self.weekdayIsWildcard = fields[4].hasPrefix("*")
    }

    public func matches(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let mn = components.minute,
            let hr = components.hour,
            let dy = components.day,
            let mo = components.month,
            let wk = components.weekday
        else { return false }
        let wkZeroIndexed = (wk - 1 + 7) % 7
        let dayMatches = day.contains(dy)
        let weekdayMatches = weekday.contains(wkZeroIndexed)
        let calendarDayMatches =
            if dayIsWildcard && weekdayIsWildcard {
                true
            } else if dayIsWildcard {
                weekdayMatches
            } else if weekdayIsWildcard {
                dayMatches
            } else {
                dayMatches || weekdayMatches
            }
        return minute.contains(mn)
            && hour.contains(hr)
            && month.contains(mo)
            && calendarDayMatches
    }

    public func next(after date: Date, calendar: Calendar) -> Date? {
        guard var probe = Self.nextFullMinute(after: date, calendar: calendar) else {
            return nil
        }
        for _ in 0..<(60 * 24 * 366 * 5) {
            if matches(probe, calendar: calendar) { return probe }
            guard let nextProbe = calendar.date(byAdding: .minute, value: 1, to: probe) else {
                return nil
            }
            probe = nextProbe
        }
        return nil
    }

    private static func nextFullMinute(after date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let floored = calendar.date(from: components) else {
            return nil
        }
        if floored > date {
            return floored
        }
        return calendar.date(byAdding: .minute, value: 1, to: floored)
    }

    private static func parse(_ field: String, range: ClosedRange<Int>) throws -> Set<Int> {
        if field == "*" { return Set(range) }
        var values: Set<Int> = []
        for part in field.split(separator: ",", omittingEmptySubsequences: false) {
            guard !part.isEmpty else {
                throw CronExpressionError.invalidField(field)
            }
            if part.contains("/") {
                let pieces = part.split(separator: "/", omittingEmptySubsequences: false)
                guard pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty,
                    let step = Int(pieces[1]), step > 0
                else {
                    throw CronExpressionError.invalidField(field)
                }
                let base = pieces[0] == "*" ? range : try Self.parseRange(String(pieces[0]), range: range)
                for v in stride(from: base.lowerBound, through: base.upperBound, by: step) {
                    values.insert(v)
                }
            } else if part.contains("-") {
                let range2 = try Self.parseRange(String(part), range: range)
                for v in range2 { values.insert(v) }
            } else if let v = Int(part), range.contains(v) {
                values.insert(v)
            } else {
                throw CronExpressionError.invalidField(field)
            }
        }
        return values
    }

    private static func parseRange(_ part: String, range: ClosedRange<Int>) throws -> ClosedRange<Int> {
        let pieces = part.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2,
            !pieces[0].isEmpty,
            !pieces[1].isEmpty,
            let lo = Int(pieces[0]),
            let hi = Int(pieces[1]),
            range.contains(lo),
            range.contains(hi),
            lo <= hi
        else { throw CronExpressionError.invalidField(part) }
        return lo...hi
    }
}
