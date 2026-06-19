import Foundation
import Testing

@testable import CalendarFeature

@Suite struct AllDayLaneLayoutTests {
    let cal = Calendar(identifier: .gregorian)
    // Mon..Sun of a fixed week
    func week(_ y: Int, _ m: Int, _ mondayDay: Int) -> [Date] {
        (0..<7).map { cal.date(from: DateComponents(year: y, month: m, day: mondayDay + $0))! }
    }

    func allDay(_ title: String, _ y: Int, _ m: Int, _ d1: Int, _ d2: Int) -> TimelineItem {
        let s = cal.date(from: DateComponents(year: y, month: m, day: d1))!
        let e = cal.date(from: DateComponents(year: y, month: m, day: d2))!  // exclusive end-of-span
        return TimelineItem(
            id: title,
            title: title,
            start: s,
            end: e,
            kind: .event,
            colorHex: nil,
            isAllDay: true,
            isConflicted: false
        )
    }

    @Test func singleDaySpansOneColumn() {
        let days = week(2026, 6, 15)
        let (bars, _) = AllDayLaneLayout.layout(
            items: [allDay("X", 2026, 6, 18, 19)],
            visibleDays: days,
            calendar: cal,
            maxLanes: 3
        )
        #expect(bars.count == 1)
        #expect(bars[0].startColumn == 3 && bars[0].endColumn == 3 && bars[0].lane == 0)
    }

    @Test func multiDaySpansContiguousColumns() {
        let days = week(2026, 6, 15)
        let (bars, _) = AllDayLaneLayout.layout(
            items: [allDay("Trip", 2026, 6, 16, 19)],
            visibleDays: days,
            calendar: cal,
            maxLanes: 3
        )
        #expect(bars[0].startColumn == 1 && bars[0].endColumn == 3)  // Tue..Thu inclusive
        #expect(bars[0].clippedStart == false && bars[0].clippedEnd == false)
    }

    @Test func clampsEventStartingBeforeWeek() {
        let days = week(2026, 6, 15)
        let (bars, _) = AllDayLaneLayout.layout(
            items: [allDay("Pre", 2026, 6, 12, 17)],
            visibleDays: days,
            calendar: cal,
            maxLanes: 3
        )
        #expect(bars[0].startColumn == 0 && bars[0].clippedStart == true)
        #expect(bars[0].endColumn == 1)  // ends Wed-exclusive -> Tue inclusive
    }

    @Test func overlappingEventsGetSeparateLanes() {
        let days = week(2026, 6, 15)
        let items = [allDay("A", 2026, 6, 15, 18), allDay("B", 2026, 6, 16, 19)]
        let (bars, _) = AllDayLaneLayout.layout(
            items: items,
            visibleDays: days,
            calendar: cal,
            maxLanes: 3
        )
        #expect(Set(bars.map(\.lane)) == Set([0, 1]))
    }

    @Test func nonOverlappingReuseLane() {
        let days = week(2026, 6, 15)
        let items = [allDay("A", 2026, 6, 15, 17), allDay("B", 2026, 6, 18, 20)]
        let (bars, _) = AllDayLaneLayout.layout(
            items: items,
            visibleDays: days,
            calendar: cal,
            maxLanes: 3
        )
        #expect(bars.allSatisfy { $0.lane == 0 })
    }

    @Test func overflowCountedPerColumnBeyondMaxLanes() {
        let days = week(2026, 6, 15)
        // 3 events all covering Mon, maxLanes 2 -> 1 overflow on column 0
        let items = (0..<3).map { allDay("E\($0)", 2026, 6, 15, 16) }
        let (bars, overflow) = AllDayLaneLayout.layout(
            items: items,
            visibleDays: days,
            calendar: cal,
            maxLanes: 2
        )
        #expect(bars.count == 2)
        #expect(overflow[0] == 1)
    }
}
