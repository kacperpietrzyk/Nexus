import Foundation
import Testing

@testable import NexusCore

@Suite("RRuleScheduler")
struct RRuleSchedulerTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return Calendar.gregorianUTC.date(from: comps)!
    }

    @Test("daily and interval")
    func daily() {
        let scheduler = RRuleScheduler(calendar: .gregorianUTC)
        #expect(scheduler.next(after: date(2026, 5, 4), rule: RRule(frequency: .daily)) == date(2026, 5, 5))
        #expect(
            scheduler.next(after: date(2026, 5, 4), rule: RRule(frequency: .daily, interval: 3))
                == date(2026, 5, 7)
        )
    }

    @Test("weekly BYDAY finds next matching day")
    func weeklyByDay() {
        let scheduler = RRuleScheduler(calendar: .gregorianUTC)
        let rule = RRule(frequency: .weekly, byWeekday: [.monday, .wednesday, .friday])
        #expect(scheduler.next(after: date(2026, 5, 5), rule: rule) == date(2026, 5, 6))
    }

    @Test("weekly BYDAY respects INTERVAL (bi-weekly does not collapse to weekly)")
    func weeklyByDayInterval() {
        let scheduler = RRuleScheduler(calendar: .gregorianUTC)
        // 2026-01-05 is a Monday. Every-other-Monday after it is 2026-01-19, not 2026-01-12.
        let biweekly = RRule(frequency: .weekly, interval: 2, byWeekday: [.monday])
        #expect(scheduler.next(after: date(2026, 1, 5), rule: biweekly) == date(2026, 1, 19))

        // Multi-day BYDAY within the same active week still advances within that week...
        let biweeklyMWF = RRule(frequency: .weekly, interval: 2, byWeekday: [.monday, .wednesday, .friday])
        #expect(scheduler.next(after: date(2026, 1, 5), rule: biweeklyMWF) == date(2026, 1, 7))
        // ...but after the last day of an active week it skips the inactive week.
        #expect(scheduler.next(after: date(2026, 1, 9), rule: biweeklyMWF) == date(2026, 1, 19))
    }

    @Test("monthly BYMONTHDAY handles same month, last day, leap, and clamp")
    func monthly() {
        let scheduler = RRuleScheduler(calendar: .gregorianUTC)
        #expect(
            scheduler.next(after: date(2026, 5, 4), rule: RRule(frequency: .monthly, byMonthDay: 15))
                == date(2026, 5, 15)
        )
        #expect(
            scheduler.next(after: date(2026, 1, 31), rule: RRule(frequency: .monthly, byMonthDay: -1))
                == date(2026, 2, 28)
        )
        #expect(
            scheduler.next(after: date(2028, 1, 31), rule: RRule(frequency: .monthly, byMonthDay: -1))
                == date(2028, 2, 29)
        )
        #expect(
            scheduler.next(after: date(2026, 1, 31), rule: RRule(frequency: .monthly, byMonthDay: 31))
                == date(2026, 2, 28)
        )
    }

    @Test("UNTIL and COUNT can stop scheduling")
    func stopConditions() {
        let scheduler = RRuleScheduler(calendar: .gregorianUTC)
        #expect(
            scheduler.next(
                after: date(2026, 5, 4),
                rule: RRule(frequency: .daily, until: date(2026, 5, 4, hour: 23))
            ) == nil
        )
        #expect(
            scheduler.next(
                after: date(2026, 5, 4),
                rule: RRule(frequency: .daily, count: 3),
                occurrencesSoFar: 3
            ) == nil
        )
    }

    @Test("DST spring-forward keeps local hour")
    func dstSpringForward() {
        let warsaw = TimeZone(identifier: "Europe/Warsaw")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = warsaw
        let scheduler = RRuleScheduler(calendar: calendar)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 23
        comps.hour = 9
        comps.timeZone = warsaw
        let after = calendar.date(from: comps)!

        let next = scheduler.next(after: after, rule: RRule(frequency: .weekly, byWeekday: [.monday]))!
        let observed = calendar.dateComponents([.year, .month, .day, .hour], from: next)
        #expect(observed.year == 2026)
        #expect(observed.month == 3)
        #expect(observed.day == 30)
        #expect(observed.hour == 9)
    }

    // MARK: - occurrences(after:rule:before:) — M2 series projection

    @Test func occurrences_dailyEnumeratesStrictlyAfterSeedAndBeforeEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let scheduler = RRuleScheduler(calendar: calendar)
        // 2026-06-08 10:00 UTC
        let seed = Date(timeIntervalSince1970: 1_780_653_600)
        let end = seed.addingTimeInterval(4 * 86_400 - 36_000)  // 2026-06-12 00:00 UTC
        let rule = RRule(frequency: .daily)

        let dates = scheduler.occurrences(after: seed, rule: rule, before: end)

        #expect(dates.count == 3)
        #expect(dates[0] == seed.addingTimeInterval(86_400))  // Jun 9 10:00
        #expect(dates[1] == seed.addingTimeInterval(2 * 86_400))  // Jun 10 10:00
        #expect(dates[2] == seed.addingTimeInterval(3 * 86_400))  // Jun 11 10:00
    }

    @Test func occurrences_respectsCountAcrossTheWalk() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let scheduler = RRuleScheduler(calendar: calendar)
        let seed = Date(timeIntervalSince1970: 1_780_653_600)
        let end = seed.addingTimeInterval(30 * 86_400)
        let rule = RRule(frequency: .daily, count: 3)

        // One occurrence already exists (the base instance) → only 2 more allowed.
        let dates = scheduler.occurrences(after: seed, rule: rule, before: end, occurrencesSoFar: 1)

        #expect(dates.count == 2)
    }

    @Test func occurrences_weeklyByDayWalksMatchingWeekdays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let scheduler = RRuleScheduler(calendar: calendar)
        // Monday 2026-06-08 09:00 UTC
        let seed = Date(timeIntervalSince1970: 1_780_909_200)
        let end = seed.addingTimeInterval(20 * 86_400)  // before Sun Jun 28
        let rule = RRule(frequency: .weekly, byWeekday: [.monday])

        let dates = scheduler.occurrences(after: seed, rule: rule, before: end)

        #expect(dates.count == 2)
        #expect(dates[0] == seed.addingTimeInterval(7 * 86_400))  // Mon Jun 15
        #expect(dates[1] == seed.addingTimeInterval(14 * 86_400))  // Mon Jun 22
    }

    @Test func occurrences_limitCapsTheWalk() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let scheduler = RRuleScheduler(calendar: calendar)
        let seed = Date(timeIntervalSince1970: 1_780_653_600)
        let end = seed.addingTimeInterval(365 * 86_400)
        let rule = RRule(frequency: .daily)

        let dates = scheduler.occurrences(after: seed, rule: rule, before: end, limit: 3)

        #expect(dates.count == 3)
    }

    @Test func occurrences_untilStopsEnumeration() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let scheduler = RRuleScheduler(calendar: calendar)
        let seed = Date(timeIntervalSince1970: 1_780_653_600)
        let until = seed.addingTimeInterval(2 * 86_400)  // Jun 10 10:00 inclusive
        let end = seed.addingTimeInterval(30 * 86_400)
        let rule = RRule(frequency: .daily, until: until)

        let dates = scheduler.occurrences(after: seed, rule: rule, before: end)

        #expect(dates.count == 2)  // Jun 9, Jun 10 — Jun 11 > UNTIL
    }
}

extension Calendar {
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
