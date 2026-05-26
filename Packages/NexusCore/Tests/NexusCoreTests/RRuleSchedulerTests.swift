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
}

extension Calendar {
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
