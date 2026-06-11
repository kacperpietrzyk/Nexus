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

    /// Forward-walk `next(after:)` to enumerate occurrence dates strictly after
    /// `seed` and strictly before `end` (M2 series projection). Honors `COUNT`
    /// (continuing from `occurrencesSoFar`, the `countSiblings + 1` convention
    /// used by `TaskItemRepository.completeTask`) and `UNTIL` via `next`'s own
    /// guards. `limit` hard-caps the walk so a degenerate rule (or a seed far
    /// in the past) can never spin — callers get a truncated, still-correct
    /// prefix. Deterministic: same input → same output.
    public func occurrences(
        after seed: Date,
        rule: RRule,
        before end: Date,
        occurrencesSoFar: Int = 0,
        limit: Int = 1024
    ) -> [Date] {
        var results: [Date] = []
        var cursor = seed
        var generated = occurrencesSoFar
        var iterations = 0
        while iterations < limit {
            iterations += 1
            guard let candidate = next(after: cursor, rule: rule, occurrencesSoFar: generated) else {
                break
            }
            // Defensive monotonicity guard: `next` always advances for the
            // supported rule subset; if it ever didn't, bail instead of looping.
            guard candidate > cursor else { break }
            guard candidate < end else { break }
            results.append(candidate)
            generated += 1
            cursor = candidate
        }
        return results
    }

    private func nextWeekly(after: Date, rule: RRule) -> Date? {
        guard !rule.byWeekday.isEmpty else {
            return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: after)
        }

        let targetWeekdays = Set(rule.byWeekday.map(Self.calendarWeekday(for:)))
        let interval = max(1, rule.interval)
        // Anchor "active" weeks on `after`'s week: a matching weekday only fires when its week is
        // an exact multiple of `interval` weeks away from `after`'s week. For interval == 1 every
        // week is active, so this is the original "first matching weekday" behavior. For interval
        // > 1 it stops bi-weekly/N-weekly BYDAY rules from collapsing to plain weekly. Scan far
        // enough to reach the next active week's last target day.
        let afterWeekStart = calendar.dateInterval(of: .weekOfYear, for: after)?.start
        let maxDays = interval * 7 + 7
        for offset in 1...maxDays {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: after) else {
                continue
            }
            guard targetWeekdays.contains(calendar.component(.weekday, from: candidate)) else {
                continue
            }
            guard interval > 1 else { return candidate }
            guard let afterWeekStart,
                let candidateWeekStart = calendar.dateInterval(of: .weekOfYear, for: candidate)?.start,
                let daysBetween = calendar.dateComponents(
                    [.day],
                    from: afterWeekStart,
                    to: candidateWeekStart
                ).day
            else {
                return candidate
            }
            if (daysBetween / 7) % interval == 0 {
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
