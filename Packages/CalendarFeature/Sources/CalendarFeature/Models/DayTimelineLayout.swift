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
    /// All-day calendar event — rendered in the pinned banner, not on the hour
    /// axis (S3a). Always false for blocks (they are timed).
    public let isAllDay: Bool
    /// M1: the block now collides with a calendar event (or another committed
    /// block). Runtime-only, computed by `BlockConflictDetector` and published
    /// via `CalendarViewModel.conflictedBlockIDs`. Always false for events.
    public let isConflicted: Bool

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        kind: Kind,
        blockID: UUID? = nil,
        colorHex: String? = nil,
        isAllDay: Bool = false,
        isConflicted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.kind = kind
        self.blockID = blockID
        self.colorHex = colorHex
        self.isAllDay = isAllDay
        self.isConflicted = isConflicted
    }
}

/// A laid-out item with vertical geometry for the hour axis.
public struct PositionedTimelineItem: Identifiable, Equatable, Sendable {
    public let item: TimelineItem
    /// Vertical offset (points) from the top of the visible axis.
    public let yOffset: CGFloat
    /// Rendered height (points), floored to a minimum so short items stay tappable.
    public let height: CGFloat
    /// Horizontal column index within its overlap cluster, `0..<columnCount` (S3b).
    public let columnIndex: Int
    /// Number of side-by-side columns the overlap cluster splits into (1 = full
    /// width, no overlap). The view divides the item area by this and offsets by
    /// `columnIndex` so overlapping events no longer occlude each other.
    public let columnCount: Int

    public var id: String { item.id }

    public init(
        item: TimelineItem,
        yOffset: CGFloat,
        height: CGFloat,
        columnIndex: Int = 0,
        columnCount: Int = 1
    ) {
        self.item = item
        self.yOffset = yOffset
        self.height = height
        self.columnIndex = columnIndex
        self.columnCount = columnCount
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
    /// Convert events + blocks into placeable items for `day`. Blocks whose id
    /// is in `conflictedBlockIDs` render conflicted (M1); the default keeps
    /// pre-M1 call sites identical.
    public static func items(
        forDay day: Date,
        events: [CalendarEvent],
        blocks: [ScheduledBlock],
        calendar: Calendar,
        conflictedBlockIDs: Set<UUID> = []
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
                    colorHex: event.calendarColorHex,
                    isAllDay: event.isAllDay
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
                    blockID: block.id,
                    isConflicted: conflictedBlockIDs.contains(block.id)
                )
            )
        }
        return items.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start
        }
    }

    /// Lay items onto the hour axis. `hourHeight` is points per hour; items are
    /// clamped to the visible `[startHour, endHour)` window. Overlapping items are
    /// assigned side-by-side columns so they never occlude each other (S3b). All-day
    /// items are excluded — they belong in the banner, not the hour axis (S3a).
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

        // Pass 1: clamp to the visible window + drop all-day / fully-outside items.
        // Sort by clamped start (tie-break id) so column assignment is deterministic.
        let visible =
            items
            .filter { !$0.isAllDay }
            .compactMap { item -> VisibleItem? in
                let clampedStart = max(item.start, axisStart)
                let clampedEnd = min(item.end, axisEnd)
                guard clampedEnd > clampedStart else { return nil }
                return VisibleItem(item: item, start: clampedStart, end: clampedEnd)
            }
            .sorted { $0.start == $1.start ? $0.item.id < $1.item.id : $0.start < $1.start }

        // Pass 2: greedy column assignment per overlap cluster. Sweeping by start
        // time, each item reuses the lowest column freed by an earlier item or opens
        // a new one; a cluster ends when an item starts at/after every active
        // column's end. The column count per cluster equals its peak concurrency.
        let columns = assignColumns(visible)

        return visible.enumerated().map { index, entry in
            let offsetSeconds = entry.start.timeIntervalSince(axisStart)
            let durationSeconds = entry.end.timeIntervalSince(entry.start)
            return PositionedTimelineItem(
                item: entry.item,
                yOffset: CGFloat(offsetSeconds / secondsPerPoint),
                height: max(metrics.minItemHeight, CGFloat(durationSeconds / secondsPerPoint)),
                columnIndex: columns[index].index,
                columnCount: columns[index].count
            )
        }
    }

    /// All-day items for `day`, for the pinned banner above the hour axis (S3a).
    public static func allDayItems(_ items: [TimelineItem]) -> [TimelineItem] {
        items.filter(\.isAllDay)
    }

    /// A timed item clamped to the visible axis window, used during column layout.
    private struct VisibleItem {
        let item: TimelineItem
        let start: Date
        let end: Date
    }

    /// Per-item `(columnIndex, columnCount)` for the start-sorted `visible` list.
    private static func assignColumns(_ visible: [VisibleItem]) -> [(index: Int, count: Int)] {
        var result = Array(repeating: (index: 0, count: 1), count: visible.count)
        var columnEnds: [Date] = []  // last end time per active column in this cluster
        var clusterMembers: [Int] = []  // indices into `visible`
        var clusterMaxEnd: Date?

        func flushCluster() {
            for memberIndex in clusterMembers {
                result[memberIndex].count = max(1, columnEnds.count)
            }
            columnEnds.removeAll(keepingCapacity: true)
            clusterMembers.removeAll(keepingCapacity: true)
            clusterMaxEnd = nil
        }

        for (index, entry) in visible.enumerated() {
            if let maxEnd = clusterMaxEnd, entry.start >= maxEnd {
                flushCluster()
            }
            // Reuse the first column whose previous item has already ended.
            let reusable = columnEnds.firstIndex { $0 <= entry.start }
            let columnIndex: Int
            if let reusable {
                columnEnds[reusable] = entry.end
                columnIndex = reusable
            } else {
                columnEnds.append(entry.end)
                columnIndex = columnEnds.count - 1
            }
            result[index].index = columnIndex
            clusterMembers.append(index)
            clusterMaxEnd = max(clusterMaxEnd ?? entry.end, entry.end)
        }
        flushCluster()
        return result
    }
}
