import Foundation
import Testing

@testable import NexusCore

@Suite struct SlotSchedulerTests {
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func event(_ s: String, _ e: String) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString, title: "x", start: at(s), end: at(e), location: nil,
            attendees: [], isVideoCall: false, urlForJoin: nil, calendarColorHex: nil,
            isAllDay: false, calendarID: nil, organizer: nil, notes: nil, meetingID: nil)
    }

    @Test func freeSlotsAreGapsBetweenEventsMeetingMinimum() {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        let sched = SlotScheduler(calendar: cal)
        let workday = DateInterval(start: at("2026-06-15T09:00:00Z"), end: at("2026-06-15T17:00:00Z"))
        let events = [
            event("2026-06-15T10:00:00Z", "2026-06-15T11:00:00Z"),
            event("2026-06-15T13:00:00Z", "2026-06-15T14:00:00Z"),
        ]
        let slots = sched.freeSlots(events: events, within: workday, minimumMinutes: 60, maximumMinutes: 120)
        // 09–10 (60), 11–13 chunked to 120, 14–17 chunked to 120 + remainder >=60
        #expect(slots.allSatisfy { $0.duration >= 3600 })
        #expect(slots.first?.start == at("2026-06-15T09:00:00Z"))
    }

    @Test func slotFindsFirstFittingGapAcrossDays() {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        let sched = SlotScheduler(calendar: cal)
        var prefs = CalendarPreferences.default
        prefs.workdayStart = DateComponents(hour: 9, minute: 0)
        prefs.workdayEnd = DateComponents(hour: 17, minute: 0)
        let day1 = at("2026-06-15T00:00:00Z")
        let busyAllDay1 = [event("2026-06-15T09:00:00Z", "2026-06-15T17:00:00Z")]
        let slot = sched.slot(
            durationMinutes: 60, within: [day1, sched.calendar.date(byAdding: .day, value: 1, to: day1)!],
            events: busyAllDay1, prefs: prefs, after: at("2026-06-15T08:00:00Z"))
        // day1 full → first fit is day2 at 09:00
        #expect(slot != nil)
        #expect(cal.component(.day, from: slot!.start) == 16)
    }

    @Test func eveningInvocationPastWorkdayEndReturnsNilWithoutTrapping() {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        let sched = SlotScheduler(calendar: cal)
        var prefs = CalendarPreferences.default
        prefs.workdayStart = DateComponents(hour: 9, minute: 0)
        prefs.workdayEnd = DateComponents(hour: 17, minute: 0)
        let day1 = at("2026-06-15T00:00:00Z")
        // `after` is 22:00, well past the 17:00 workday end: max(start, after) > end
        // would trap when constructing the clamped DateInterval. Must skip the day
        // and return nil instead of crashing.
        let slot = sched.slot(
            durationMinutes: 60, within: [day1],
            events: [], prefs: prefs, after: at("2026-06-15T22:00:00Z"))
        #expect(slot == nil)
    }

    @Test func zeroAndNegativeDurationReturnEmptyWithoutHanging() {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        let sched = SlotScheduler(calendar: cal)
        let workday = DateInterval(start: at("2026-06-15T09:00:00Z"), end: at("2026-06-15T17:00:00Z"))
        // A non-positive minimum never advances the chunk cursor -> would spin
        // forever. Both must short-circuit to [].
        #expect(sched.freeSlots(events: [], within: workday, minimumMinutes: 0, maximumMinutes: 0).isEmpty)
        #expect(sched.freeSlots(events: [], within: workday, minimumMinutes: -30, maximumMinutes: 0).isEmpty)
        #expect(
            sched.freeSlots(
                events: [], within: workday, minimumDuration: 0, maximumDuration: .infinity
            ).isEmpty)

        // And `slot()` with a non-positive duration safely returns nil (no hang).
        var prefs = CalendarPreferences.default
        prefs.workdayStart = DateComponents(hour: 9, minute: 0)
        prefs.workdayEnd = DateComponents(hour: 17, minute: 0)
        let result = sched.slot(
            durationMinutes: 0, within: [at("2026-06-15T00:00:00Z")],
            events: [], prefs: prefs, after: at("2026-06-15T08:00:00Z"))
        #expect(result == nil)
    }
}
