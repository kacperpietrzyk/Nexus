import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("QuietHours")
struct QuietHoursTests {

    private func cal() -> Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .gmt
        return c
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("contains true for a time inside an evening window")
    func eveningInside() {
        let q = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        #expect(q.contains(date("2026-05-05T23:30:00Z"), calendar: cal()))
    }

    @Test("contains true for a time inside the morning tail of a wraparound window")
    func morningInside() {
        let q = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        #expect(q.contains(date("2026-05-05T02:00:00Z"), calendar: cal()))
    }

    @Test("contains false during the day")
    func daytime() {
        let q = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        #expect(!q.contains(date("2026-05-05T13:00:00Z"), calendar: cal()))
    }

    @Test("nextActive defers a 23:30 trigger to 07:00 next day")
    func deferEveningToMorning() {
        let q = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        let input = date("2026-05-05T23:30:00Z")
        let active = q.nextActive(after: input, calendar: cal())
        #expect(active == date("2026-05-06T07:00:00Z"))
    }

    @Test("nextActive returns input unchanged outside quiet window")
    func passthrough() {
        let q = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        let input = date("2026-05-05T13:00:00Z")
        #expect(q.nextActive(after: input, calendar: cal()) == input)
    }
}
