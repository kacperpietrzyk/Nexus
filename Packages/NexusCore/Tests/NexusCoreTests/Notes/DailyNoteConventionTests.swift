import Foundation
import Testing

@testable import NexusCore

struct DailyNoteConventionTests {
    /// Gregorian UTC calendar so expectations are machine-independent.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func dayKeyMatchesAgentBriefFormat() {
        let calendar = utc
        let noon = date(2026, 6, 11, hour: 12, calendar: calendar)
        #expect(DailyNoteConvention.dayKey(for: noon, calendar: calendar) == "2026-06-11")
    }

    @Test func titleMatchesAgentBriefWriterTitle() {
        let calendar = utc
        let day = date(2023, 11, 14, calendar: calendar)
        // Pinned to the exact value AgentBriefServiceTests asserts the writer produces.
        #expect(DailyNoteConvention.title(for: day, calendar: calendar) == "Daily Brief 2023-11-14")
    }

    @Test func tagsMatchAgentBriefWriterTags() {
        let calendar = utc
        let day = date(2023, 11, 14, calendar: calendar)
        #expect(DailyNoteConvention.tags(for: day, calendar: calendar) == ["daily", "2023-11-14"])
    }

    @Test func dateFromTitleRoundTrips() {
        let calendar = utc
        let day = date(2026, 6, 11, calendar: calendar)
        let title = DailyNoteConvention.title(for: day, calendar: calendar)
        #expect(DailyNoteConvention.date(fromTitle: title, calendar: calendar) == day)
    }

    @Test func dateFromTitleRejectsNonConventionTitles() {
        let calendar = utc
        #expect(DailyNoteConvention.date(fromTitle: "Groceries", calendar: calendar) == nil)
        #expect(DailyNoteConvention.date(fromTitle: "Daily Brief", calendar: calendar) == nil)
        #expect(DailyNoteConvention.date(fromTitle: "Daily Brief tomorrow", calendar: calendar) == nil)
    }

    @Test func dayKeyRespectsCalendarTimeZone() {
        // 2026-06-11 03:00 UTC is still 2026-06-10 in UTC-5.
        var utcMinus5 = Calendar(identifier: .gregorian)
        utcMinus5.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        let instant = date(2026, 6, 11, hour: 3, calendar: utc)
        #expect(DailyNoteConvention.dayKey(for: instant, calendar: utcMinus5) == "2026-06-10")
        #expect(DailyNoteConvention.dayKey(for: instant, calendar: utc) == "2026-06-11")
    }
}
