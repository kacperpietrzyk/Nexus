import Foundation
import NexusCore

/// One placeable item on the day hour-axis (spec §9). Either an external calendar
/// event or a Nexus `ScheduledBlock` (proposed or accepted), reduced to a
/// rendering-friendly value (the `@Model` block is not carried here — its `id`
/// re-fetches it for actions).
public struct TimelineItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case event
        case proposedBlock
        case acceptedBlock
    }

    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let kind: Kind
    /// Block id when `kind` is a block; nil for events.
    public let blockID: UUID?
    public let colorHex: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        kind: Kind,
        blockID: UUID? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.kind = kind
        self.blockID = blockID
        self.colorHex = colorHex
    }
}

/// A laid-out item with vertical geometry for the hour axis.
public struct PositionedTimelineItem: Identifiable, Equatable, Sendable {
    public let item: TimelineItem
    /// Vertical offset (points) from the top of the visible axis.
    public let yOffset: CGFloat
    /// Rendered height (points), floored to a minimum so short items stay tappable.
    public let height: CGFloat

    public var id: String { item.id }

    public init(item: TimelineItem, yOffset: CGFloat, height: CGFloat) {
        self.item = item
        self.yOffset = yOffset
        self.height = height
    }
}

/// Vertical metrics of the rendered hour axis (spec §9). Bundled so the layout
/// entry point stays cohesive.
public struct AxisMetrics: Equatable, Sendable {
    public let startHour: Int
    public let endHour: Int
    public let hourHeight: CGFloat
    public let minItemHeight: CGFloat

    public init(startHour: Int, endHour: Int, hourHeight: CGFloat, minItemHeight: CGFloat = 22) {
        self.startHour = startHour
        self.endHour = endHour
        self.hourHeight = hourHeight
        self.minItemHeight = minItemHeight
    }
}

/// Pure hour-axis layout (spec §9). Deterministic: same items + metrics → same
/// geometry. No UI, no ambient clock — fully unit-testable.
public enum DayTimelineLayout {
    /// Convert events + blocks into placeable items for `day`.
    public static func items(
        forDay day: Date,
        events: [CalendarEvent],
        blocks: [ScheduledBlock],
        calendar: Calendar
    ) -> [TimelineItem] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        var items: [TimelineItem] = []
        for event in events where event.end > dayStart && event.start < dayEnd {
            items.append(
                TimelineItem(
                    id: "event-\(event.id)",
                    title: event.title,
                    start: event.start,
                    end: event.end,
                    kind: .event,
                    colorHex: event.calendarColorHex
                )
            )
        }
        for block in blocks where block.deletedAt == nil && block.end > dayStart && block.start < dayEnd {
            items.append(
                TimelineItem(
                    id: "block-\(block.id.uuidString)",
                    title: block.title.isEmpty ? "Scheduled" : block.title,
                    start: block.start,
                    end: block.end,
                    kind: block.status == .accepted ? .acceptedBlock : .proposedBlock,
                    blockID: block.id
                )
            )
        }
        return items.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start
        }
    }

    /// Lay items onto the hour axis. `hourHeight` is points per hour; items are
    /// clamped to the visible `[startHour, endHour)` window.
    public static func layout(
        _ items: [TimelineItem],
        forDay day: Date,
        metrics: AxisMetrics,
        calendar: Calendar
    ) -> [PositionedTimelineItem] {
        let dayStart = calendar.startOfDay(for: day)
        let axisStart = calendar.date(byAdding: .hour, value: metrics.startHour, to: dayStart) ?? dayStart
        let axisEnd = calendar.date(byAdding: .hour, value: metrics.endHour, to: dayStart) ?? dayStart
        let secondsPerPoint = 3600.0 / Double(metrics.hourHeight)

        return items.compactMap { item -> PositionedTimelineItem? in
            let clampedStart = max(item.start, axisStart)
            let clampedEnd = min(item.end, axisEnd)
            guard clampedEnd > clampedStart else { return nil }

            let offsetSeconds = clampedStart.timeIntervalSince(axisStart)
            let durationSeconds = clampedEnd.timeIntervalSince(clampedStart)
            let yOffset = CGFloat(offsetSeconds / secondsPerPoint)
            let height = max(metrics.minItemHeight, CGFloat(durationSeconds / secondsPerPoint))
            return PositionedTimelineItem(item: item, yOffset: yOffset, height: height)
        }
    }
}
