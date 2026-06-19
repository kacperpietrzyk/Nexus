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

    // MARK: - Overlap columns (S3b)

    private func timed(_ id: String, _ startHour: Double, _ endHour: Double) -> TimelineItem {
        TimelineItem(
            id: id,
            title: id,
            start: dayStart.addingTimeInterval(startHour * 3600),
            end: dayStart.addingTimeInterval(endHour * 3600),
            kind: .event
        )
    }

    private func layout(_ items: [TimelineItem]) -> [PositionedTimelineItem] {
        DayTimelineLayout.layout(
            items,
            forDay: dayStart,
            metrics: AxisMetrics(startHour: 8, endHour: 18, hourHeight: 60),
            calendar: calendar
        )
    }

    @Test("Non-overlapping items each get a single full-width column")
    func nonOverlappingSingleColumn() {
        let result = layout([timed("a", 9, 10), timed("b", 11, 12)])
        #expect(result.allSatisfy { $0.columnCount == 1 && $0.columnIndex == 0 })
    }

    @Test("Two overlapping items split into two side-by-side columns")
    func twoOverlapTwoColumns() {
        let result = layout([timed("a", 9, 10.5), timed("b", 10, 11)])
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.columnCount == 2 })
        #expect(Set(result.map(\.columnIndex)) == [0, 1])
    }

    @Test("Three mutually overlapping items use three columns")
    func threeMutualOverlap() {
        let result = layout([timed("a", 9, 11), timed("b", 9.5, 11), timed("c", 10, 11)])
        #expect(result.allSatisfy { $0.columnCount == 3 })
        #expect(Set(result.map(\.columnIndex)) == [0, 1, 2])
    }

    @Test("A freed column is reused within a cluster (chain stays at 2 columns)")
    func chainReusesColumn() {
        // a 9–10, b 9:30–10:30, c 10:15–11. Max concurrency in the cluster is 2;
        // c reuses a's freed column → columnCount 2 for the whole cluster.
        let result = layout([timed("a", 9, 10), timed("b", 9.5, 10.5), timed("c", 10.25, 11)])
        #expect(result.allSatisfy { $0.columnCount == 2 })
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.item.id, $0.columnIndex) })
        #expect(byID["a"] == 0)
        #expect(byID["b"] == 1)
        #expect(byID["c"] == 0)  // reuses a's column
    }

    // MARK: - All-day banner (S3a)

    @Test("All-day events are excluded from the hour axis and surfaced separately")
    func allDayExcludedFromAxis() {
        let cal = calendar
        let allDay = CalendarEvent(
            id: "holiday",
            title: "Holiday",
            start: dayStart,
            end: dayStart.addingTimeInterval(86_400),
            isAllDay: true
        )
        let timedEvent = CalendarEvent(
            id: "standup",
            title: "Standup",
            start: dayStart.addingTimeInterval(9 * 3600),
            end: dayStart.addingTimeInterval(9 * 3600 + 1800)
        )
        let items = DayTimelineLayout.items(forDay: dayStart, events: [allDay, timedEvent], blocks: [], calendar: cal)

        // The all-day flag round-trips, the banner sees only it, and the hour axis
        // never lays it out (no more 24h block).
        #expect(DayTimelineLayout.allDayItems(items).map(\.id) == ["event-holiday"])
        let positioned = layout(items)
        #expect(positioned.map(\.item.id) == ["event-standup"])
    }

    @Test("Separate overlap clusters get independent column counts")
    func independentClusters() {
        // Cluster 1: a+b overlap (2 cols). Gap. Cluster 2: c alone (1 col).
        let result = layout([timed("a", 9, 10), timed("b", 9.5, 10.5), timed("c", 14, 15)])
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.item.id, $0.columnCount) })
        #expect(byID["a"] == 2)
        #expect(byID["b"] == 2)
        #expect(byID["c"] == 1)
    }

    @Test("series previews map to .seriesPreview items clipped to the day, with no blockID")
    func seriesPreviewsBecomeTimelineItems() {
        let cal = calendar
        let day = dayStart
        let preview = SeriesOccurrencePreview(
            seriesID: UUID(),
            taskID: UUID(),
            occurrenceDate: day.addingTimeInterval(10 * 3600),
            start: day.addingTimeInterval(9 * 3600),
            end: day.addingTimeInterval(10 * 3600),
            title: "standup"
        )
        let otherDayPreview = SeriesOccurrencePreview(
            seriesID: UUID(),
            taskID: UUID(),
            occurrenceDate: day.addingTimeInterval(86_400 + 10 * 3600),
            start: day.addingTimeInterval(86_400 + 9 * 3600),
            end: day.addingTimeInterval(86_400 + 10 * 3600),
            title: "tomorrow"
        )

        let items = DayTimelineLayout.items(
            forDay: day,
            events: [],
            blocks: [],
            calendar: cal,
            seriesPreviews: [preview, otherDayPreview]
        )

        #expect(items.count == 1)
        let item = items[0]
        #expect(item.kind == .seriesPreview)
        #expect(item.id == preview.id)
        #expect(item.title == "standup")
        #expect(item.blockID == nil)
        #expect(item.isAllDay == false)
        #expect(item.isConflicted == false)
    }

    @Test("omitting seriesPreviews leaves existing call sites byte-identical")
    func defaultParameterAddsNothing() {
        let items = DayTimelineLayout.items(forDay: dayStart, events: [], blocks: [], calendar: calendar)
        #expect(items.isEmpty)
    }

    // MARK: - Subtitle data (Task 5)

    @Test("items() carries location and organizer name into TimelineItem")
    func subtitleDataCarriedThrough() {
        let cal = calendar
        let organizer = CalendarEvent.Attendee(name: "Kamil")
        let event = CalendarEvent(
            id: "e-subtitle",
            title: "Design Review",
            start: dayStart.addingTimeInterval(10 * 3600),
            end: dayStart.addingTimeInterval(11 * 3600),
            location: "Sala Galaxy",
            organizer: organizer
        )

        let items = DayTimelineLayout.items(
            forDay: dayStart,
            events: [event],
            blocks: [],
            calendar: cal
        )

        #expect(items.count == 1)
        #expect(items[0].location == "Sala Galaxy")
        #expect(items[0].organizer == "Kamil")
    }
}
