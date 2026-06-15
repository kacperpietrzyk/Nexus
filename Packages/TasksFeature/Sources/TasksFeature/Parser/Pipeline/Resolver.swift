import Foundation
import NexusCore

internal struct Resolver: Sendable {
    func resolve(
        _ tokens: [Token],
        locale: LocalePhrases,
        now: Date,
        calendar: Calendar = ParserCalendar.production
    ) -> [Token] {
        tokens.map { token in
            switch token {
            case .dateLiteral(let raw, _):
                if let interpreted = interpretDateLiteral(raw, now: now, calendar: calendar) {
                    return interpreted
                }
                return .residual(raw)
            case .dayKeyword(let weekday, let confidence):
                let offset = nextWeekdayOffset(weekday, from: now, calendar: calendar)
                return .relativeDay(offset: offset, confidence: confidence)
            default:
                return token
            }
        }
    }

    private func interpretDateLiteral(_ raw: String, now: Date, calendar: Calendar) -> Token? {
        // ISO yyyy-MM-dd
        if let date = parseDate(raw, format: "yyyy-MM-dd", calendar: calendar) {
            return .relativeDay(offset: dayOffset(from: now, to: date, calendar: calendar), confidence: 0.95)
        }
        // DD.MM.YYYY
        if let date = parseDate(raw, format: "dd.MM.yyyy", calendar: calendar) {
            return .relativeDay(offset: dayOffset(from: now, to: date, calendar: calendar), confidence: 0.95)
        }
        // DD.MM (roll to next occurrence on or after now)
        if let date = parsePartialDate(raw, format: "dd.MM", now: now, calendar: calendar) {
            return .relativeDay(offset: dayOffset(from: now, to: date, calendar: calendar), confidence: 0.85)
        }
        // HH:MM (treat as time-of-day on today)
        if let secs = parseTimeOfDay(raw) {
            return .timeOfDay(secondsIntoDay: secs, confidence: 0.9)
        }
        return nil
    }

    private func parseDate(_ raw: String, format: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter.date(from: raw)
    }

    private func parsePartialDate(_ raw: String, format: String, now: Date, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        guard let parsed = formatter.date(from: raw) else { return nil }

        let nowComponents = calendar.dateComponents([.year], from: now)
        var components = calendar.dateComponents([.month, .day], from: parsed)
        components.year = nowComponents.year
        // Reject — don't lenient-roll — a day invalid for the resolved month/year
        // (e.g. "29.02" in a non-leap year would otherwise become 1 Mar).
        guard let candidate = validatedDate(from: components, calendar: calendar) else { return nil }

        let nowDay = calendar.startOfDay(for: now)
        let candidateDay = calendar.startOfDay(for: candidate)
        if candidateDay < nowDay {
            components.year = (components.year ?? 1970) + 1
            // The +1-year rollover can also land on an invalid day (29 Feb in a
            // following non-leap year); reject rather than silently roll over.
            return validatedDate(from: components, calendar: calendar)
        }
        return candidate
    }

    /// Builds a date from `components` only if the calendar reproduces the exact
    /// year/month/day requested. `Calendar.date(from:)` is lenient and normalizes
    /// out-of-range days (29 Feb in a non-leap year → 1 Mar), so we round-trip and
    /// reject any mismatch.
    private func validatedDate(from components: DateComponents, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == components.year,
            resolved.month == components.month,
            resolved.day == components.day
        else { return nil }
        return date
    }

    private func parseTimeOfDay(_ raw: String) -> TimeInterval? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0..<24).contains(hour),
            (0..<60).contains(minute)
        else { return nil }
        return TimeInterval(hour * 3600 + minute * 60)
    }

    private func dayOffset(from now: Date, to date: Date, calendar: Calendar) -> Int {
        let nowDay = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: nowDay, to: target).day ?? 0
    }

    private func nextWeekdayOffset(_ target: RRule.Weekday, from now: Date, calendar: Calendar) -> Int {
        // Calendar weekday: 1=Sunday..7=Saturday. RRule.Weekday: monday=2..sunday=1.
        let nowWeekday = calendar.component(.weekday, from: now)
        let targetWeekday = calendarWeekday(for: target)
        var diff = targetWeekday - nowWeekday
        if diff <= 0 { diff += 7 }  // strict-future: today's name skips a week
        return diff
    }

    private func calendarWeekday(for w: RRule.Weekday) -> Int {
        switch w {
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
