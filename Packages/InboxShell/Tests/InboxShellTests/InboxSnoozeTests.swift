import Foundation
import Testing

/// Tests for the "snooze tomorrow at 9 AM" date derivation used in
/// `InboxView.snoozeTomorrow(_:)`. The function itself is private to the
/// view, so we replicate the pure Calendar arithmetic here so the key
/// invariant (tomorrow/09:00 in local time) has a regression safety net
/// without exposing view internals.
@Suite("Snooze date helpers")
struct InboxSnoozeTests {

    // Reproduce the same logic as InboxView.snoozeTomorrow.
    private func snoozeTomorrowDate(from now: Date, calendar: Calendar) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    @Test("snooze tomorrow lands on the next calendar day at 09:00")
    func snoozeTomorrowIsNextDayAt9AM() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        // Reference: 2024-01-15 at 14:30 Warsaw time.
        let components = DateComponents(
            timeZone: cal.timeZone,
            year: 2024, month: 1, day: 15, hour: 14, minute: 30
        )
        let now = cal.date(from: components)!
        let result = snoozeTomorrowDate(from: now, calendar: cal)
        let resultComponents = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result)
        #expect(resultComponents.year == 2024)
        #expect(resultComponents.month == 1)
        #expect(resultComponents.day == 16)
        #expect(resultComponents.hour == 9)
        #expect(resultComponents.minute == 0)
        #expect(resultComponents.second == 0)
    }

    @Test("snooze tomorrow crosses a month boundary correctly")
    func snoozeTomorrowCrossesMonthBoundary() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // 2024-01-31 at 23:50 UTC — tomorrow = 2024-02-01.
        let components = DateComponents(
            timeZone: cal.timeZone,
            year: 2024, month: 1, day: 31, hour: 23, minute: 50
        )
        let now = cal.date(from: components)!
        let result = snoozeTomorrowDate(from: now, calendar: cal)
        let resultComponents = cal.dateComponents([.year, .month, .day, .hour], from: result)
        #expect(resultComponents.year == 2024)
        #expect(resultComponents.month == 2)
        #expect(resultComponents.day == 1)
        #expect(resultComponents.hour == 9)
    }

    @Test("snooze tomorrow is always strictly after now")
    func snoozeTomorrowIsAlwaysInFuture() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Use a time after 09:00 so the result can't accidentally be in the past.
        let components = DateComponents(
            timeZone: cal.timeZone,
            year: 2025, month: 6, day: 18, hour: 10, minute: 0
        )
        let now = cal.date(from: components)!
        let result = snoozeTomorrowDate(from: now, calendar: cal)
        #expect(result > now)
    }
}
