import Foundation
import NexusCore
import Testing

@testable import CalendarFeature

@Suite("DayTimelineLayout")
struct DayTimelineLayoutTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // 2026-06-08 00:00 UTC
    private let dayStart = Date(timeIntervalSince1970: 1_780_617_600)

    @Test("Items include events and blocks, distinguishing proposed vs accepted")
    func itemsKinds() {
        let cal = calendar
        let event = CalendarEvent(
            id: "e1",
            title: "Standup",
            start: dayStart.addingTimeInterval(9 * 3600),
            end: dayStart.addingTimeInterval(9 * 3600 + 1800)
        )
        let proposed = ScheduledBlock(
            taskID: UUID(),
            start: dayStart.addingTimeInterval(10 * 3600),
            end: dayStart.addingTimeInterval(11 * 3600),
            title: "Deep work",
            status: .proposed
        )
        let accepted = ScheduledBlock(
            taskID: UUID(),
            start: dayStart.addingTimeInterval(13 * 3600),
            end: dayStart.addingTimeInterval(14 * 3600),
            title: "Review",
            status: .accepted,
            externalEventID: "evt"
        )

        let items = DayTimelineLayout.items(
            forDay: dayStart,
            events: [event],
            blocks: [proposed, accepted],
            calendar: cal
        )

        #expect(items.count == 3)
        #expect(items.contains { $0.kind == .event && $0.title == "Standup" })
        #expect(items.contains { $0.kind == .proposedBlock && $0.blockID == proposed.id })
        #expect(items.contains { $0.kind == .acceptedBlock && $0.blockID == accepted.id })
    }

    @Test("Soft-deleted blocks are excluded")
    func excludesDeleted() {
        let cal = calendar
        let block = ScheduledBlock(
            taskID: UUID(),
            start: dayStart.addingTimeInterval(10 * 3600),
            end: dayStart.addingTimeInterval(11 * 3600),
            status: .proposed
        )
        block.deletedAt = dayStart
        let items = DayTimelineLayout.items(forDay: dayStart, events: [], blocks: [block], calendar: cal)
        #expect(items.isEmpty)
    }

    @Test("Layout positions an item by hour with deterministic geometry")
    func layoutGeometry() {
        let cal = calendar
        let item = TimelineItem(
            id: "x",
            title: "Block",
            start: dayStart.addingTimeInterval(10 * 3600),  // 10:00
            end: dayStart.addingTimeInterval(11 * 3600),  // 11:00
            kind: .proposedBlock
        )
        let positioned = DayTimelineLayout.layout(
            [item],
            forDay: dayStart,
            metrics: AxisMetrics(startHour: 8, endHour: 18, hourHeight: 60),
            calendar: cal
        )
        #expect(positioned.count == 1)
        // 10:00 is 2 hours after the 08:00 axis start → 120pt.
        #expect(positioned[0].yOffset == 120)
        // 1-hour duration at 60pt/hr → 60pt.
        #expect(positioned[0].height == 60)
    }

    @Test("Layout clamps items to the visible window and drops fully-outside items")
    func layoutClamps() {
        let cal = calendar
        let before = TimelineItem(
            id: "before",
            title: "Early",
            start: dayStart.addingTimeInterval(6 * 3600),
            end: dayStart.addingTimeInterval(7 * 3600),
            kind: .event
        )
        let result = DayTimelineLayout.layout(
            [before],
            forDay: dayStart,
            metrics: AxisMetrics(startHour: 8, endHour: 18, hourHeight: 60),
            calendar: cal
        )
        #expect(result.isEmpty)
    }

    @Test("Short items keep a minimum tappable height")
    func minHeight() {
        let cal = calendar
        let tiny = TimelineItem(
            id: "tiny",
            title: "Quick",
            start: dayStart.addingTimeInterval(9 * 3600),
            end: dayStart.addingTimeInterval(9 * 3600 + 300),  // 5 min
            kind: .event
        )
        let result = DayTimelineLayout.layout(
            [tiny],
            forDay: dayStart,
            metrics: AxisMetrics(startHour: 8, endHour: 18, hourHeight: 60, minItemHeight: 22),
            calendar: cal
        )
        #expect(result[0].height == 22)
    }
}
