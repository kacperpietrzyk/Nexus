import Foundation

/// Computes the next occurrence date for an `RRule` using `Calendar` arithmetic.
public struct RRuleScheduler: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func next(
        after: Date,
        rule: RRule,
        occurrencesSoFar: Int = 0
    ) -> Date? {
        if let count = rule.count, occurrencesSoFar >= count {
            return nil
        }

        let candidate: Date?
        switch rule.frequency {
        case .daily:
            candidate = calendar.date(byAdding: .day, value: rule.interval, to: after)
        case .weekly:
            candidate = nextWeekly(after: after, rule: rule)
        case .monthly:
            candidate = nextMonthly(after: after, rule: rule)
        }

        guard let candidate else { return nil }
        if let until = rule.until, candidate > until {
            return nil
        }
        return candidate
    }

    private func nextWeekly(after: Date, rule: RRule) -> Date? {
        guard !rule.byWeekday.isEmpty else {
            return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: after)
        }

        let targetWeekdays = Set(rule.byWeekday.map(Self.calendarWeekday(for:)))
        let maxDays = max(1, rule.interval * 7)
        for offset in 1...maxDays {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: after) else {
                continue
            }
            if targetWeekdays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
        }
        return nil
    }

    private func nextMonthly(after: Date, rule: RRule) -> Date? {
        guard let byMonthDay = rule.byMonthDay else {
            return calendar.date(byAdding: .month, value: rule.interval, to: after)
        }

        if let sameMonthCandidate = resolveDay(
            from: after,
            addingMonths: 0,
            byMonthDay: byMonthDay
        ), sameMonthCandidate > after {
            return sameMonthCandidate
        }

        return resolveDay(from: after, addingMonths: rule.interval, byMonthDay: byMonthDay)
    }

    private func resolveDay(from date: Date, addingMonths: Int, byMonthDay: Int) -> Date? {
        guard let base = calendar.date(byAdding: .month, value: addingMonths, to: date) else {
            return nil
        }
        var comps = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: base)
        guard let year = comps.year, let month = comps.month else { return nil }
        comps.day = targetDay(byMonthDay: byMonthDay, year: year, month: month)
        return calendar.date(from: comps)
    }

    private func targetDay(byMonthDay: Int, year: Int, month: Int) -> Int {
        let lastDay = lastDayOfMonth(year: year, month: month)
        if byMonthDay == -1 {
            return lastDay
        }
        return min(byMonthDay, lastDay)
    }

    private func lastDayOfMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = calendar.date(from: comps),
            let range = calendar.range(of: .day, in: .month, for: first)
        else {
            return 28
        }
        return range.count
    }

    private static func calendarWeekday(for weekday: RRule.Weekday) -> Int {
        switch weekday {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }
}
