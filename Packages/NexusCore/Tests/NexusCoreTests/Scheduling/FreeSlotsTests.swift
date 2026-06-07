import Foundation
import Testing

@testable import NexusCore

@Suite("FreeSlotComputer")
struct FreeSlotsTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 6, day: 8, hour: hour, minute: minute
        ).date!
    }

    private var prefs: CalendarPreferences {
        CalendarPreferences(
            workdayStart: DateComponents(hour: 9, minute: 0),
            workdayEnd: DateComponents(hour: 18, minute: 0),
            minBlockMinutes: 15,
            maxBlockMinutes: 120,
            bufferMinutes: 0
        )
    }

    private func event(_ s: Int, _ e: Int) -> CalendarEvent {
        CalendarEvent(id: UUID().uuidString, title: "e", start: at(s), end: at(e))
    }

    private func freeSlots(
        events: [CalendarEvent] = [],
        accepted: [ScheduledBlock] = [],
        prefs: CalendarPreferences? = nil
    ) -> [FreeSlot] {
        FreeSlotComputer.freeSlots(
            forDayContaining: at(9),
            events: events,
            acceptedBlocks: accepted,
            prefs: prefs ?? self.prefs,
            calendar: calendar
        )
    }

    @Test("empty day → one slot spanning the whole window")
    func emptyDay() {
        let slots = freeSlots()
        #expect(slots.count == 1)
        #expect(slots[0].start == at(9))
        #expect(slots[0].end == at(18))
    }

    @Test("one event splits the window into two slots")
    func oneEvent() {
        let slots = freeSlots(events: [event(12, 13)])
        #expect(slots.count == 2)
        #expect(slots[0].end == at(12))
        #expect(slots[1].start == at(13))
    }

    @Test("overlapping events merge before subtraction")
    func overlappingMerge() {
        let slots = freeSlots(events: [event(11, 13), event(12, 14)])
        #expect(slots.count == 2)
        #expect(slots[0].end == at(11))
        #expect(slots[1].start == at(14))
    }

    @Test("accepted blocks are obstacles too")
    func acceptedAreObstacles() {
        let block = ScheduledBlock(taskID: UUID(), start: at(10), end: at(11), status: .accepted, externalEventID: "x")
        let slots = freeSlots(accepted: [block])
        #expect(slots.count == 2)
        #expect(slots[0].end == at(10))
        #expect(slots[1].start == at(11))
    }

    @Test("buffer pads obstacles")
    func bufferPads() {
        var padded = prefs
        padded.bufferMinutes = 30
        let slots = freeSlots(events: [event(12, 13)], prefs: padded)
        #expect(slots[0].end == at(11, 30))
        #expect(slots[1].start == at(13, 30))
    }

    @Test("residual gap below minBlock is discarded")
    func discardTinyGap() {
        // Event 09:10–18:00 leaves a 10m gap (< 15m min) at the start.
        let blocking = CalendarEvent(id: "b", title: "e", start: at(9, 10), end: at(18))
        let slots = freeSlots(events: [blocking])
        // The 10m head gap is dropped; nothing else free.
        #expect(slots.isEmpty)
    }

    @Test("soft-deleted accepted block is ignored")
    func deletedBlockIgnored() {
        let block = ScheduledBlock(taskID: UUID(), start: at(10), end: at(11), status: .accepted, externalEventID: "x")
        block.deletedAt = at(9)
        let slots = freeSlots(accepted: [block])
        #expect(slots.count == 1)
    }
}
