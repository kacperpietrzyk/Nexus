import Foundation

/// A laid-out all-day bar for the multi-day spanning banner (spec §9 / S3a).
/// `startColumn` and `endColumn` are inclusive, clamped to `0..<visibleDays.count`.
public struct AllDayBar: Equatable, Sendable {
    public let item: TimelineItem
    /// 0-based index into `visibleDays`, clamped.
    public let startColumn: Int
    /// Inclusive last column, clamped to `visibleDays.count - 1`.
    public let endColumn: Int
    /// 0-based row within the all-day lane grid.
    public let lane: Int
    /// Event began before `visibleDays.first`.
    public let clippedStart: Bool
    /// Event ends after `visibleDays.last`.
    public let clippedEnd: Bool
}

/// Pure-logic layout engine that places all-day `TimelineItem`s into a grid of
/// horizontal bars (columns = days, rows = lanes). Call sites own the rendering.
///
/// Algorithm
/// ---------
/// 1. Filter to `isAllDay` items; drop those with no overlap with the visible range.
/// 2. Map `start`/`end` to `[startColumn, endColumn]` via day-offset arithmetic.
///    `end` is exclusive; last covered column = `startOfDay(end - 1s)`.
/// 3. Sort by `(startColumn ASC, span DESC, id ASC)` for stable greedy packing.
/// 4. Greedy lowest-free-lane: place each bar in the lowest lane with no column overlap.
/// 5. Bars needing lane `>= maxLanes` are dropped; every covered column increments overflow.
public enum AllDayLaneLayout {
    /// - Parameters:
    ///   - items:       All `TimelineItem`s (non–all-day items are silently skipped).
    ///   - visibleDays: Ordered day-start `Date`s (1 for Day view, 7 for Week view).
    ///   - calendar:    Used for all day-boundary computations.
    ///   - maxLanes:    Bars beyond this row count are dropped and tallied into overflow.
    /// - Returns: Placed bars in stable order; overflow counts keyed by column index.
    public static func layout(
        items: [TimelineItem],
        visibleDays: [Date],
        calendar: Calendar,
        maxLanes: Int
    ) -> (bars: [AllDayBar], overflowByColumn: [Int: Int]) {
        guard !visibleDays.isEmpty else { return ([], [:]) }
        let count = visibleDays.count
        let firstDay = calendar.startOfDay(for: visibleDays[0])
        let lastDay = calendar.startOfDay(for: visibleDays[count - 1])
        let afterLast = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay

        var candidates = buildCandidates(
            from: items,
            firstDay: firstDay,
            afterLast: afterLast,
            count: count,
            calendar: calendar
        )
        candidates.sort {
            if $0.startColumn != $1.startColumn { return $0.startColumn < $1.startColumn }
            if $0.span != $1.span { return $0.span > $1.span }
            return $0.item.id < $1.item.id
        }
        return packLanes(candidates: candidates, maxLanes: maxLanes)
    }

    // MARK: - Private helpers

    struct Candidate {
        let item: TimelineItem
        let startColumn: Int
        let endColumn: Int
        let span: Int
        let clippedStart: Bool
        let clippedEnd: Bool
    }

    private static func buildCandidates(
        from items: [TimelineItem],
        firstDay: Date,
        afterLast: Date,
        count: Int,
        calendar: Calendar
    ) -> [Candidate] {
        var result: [Candidate] = []
        for item in items where item.isAllDay {
            let rawStart = calendar.startOfDay(for: item.start)
            let rawEnd = calendar.startOfDay(for: item.end.addingTimeInterval(-1))
            // Drop items entirely outside the visible range.
            if rawEnd < firstDay || rawStart >= afterLast { continue }

            let rawStartCol = calendar.dateComponents([.day], from: firstDay, to: rawStart).day ?? 0
            let rawEndCol = calendar.dateComponents([.day], from: firstDay, to: rawEnd).day ?? 0
            let startColumn = max(0, rawStartCol)
            let endColumn = min(count - 1, rawEndCol)

            result.append(
                Candidate(
                    item: item,
                    startColumn: startColumn,
                    endColumn: endColumn,
                    span: endColumn - startColumn,
                    clippedStart: rawStartCol < 0,
                    clippedEnd: rawEndCol >= count
                )
            )
        }
        return result
    }

    private static func packLanes(
        candidates: [Candidate],
        maxLanes: Int
    ) -> (bars: [AllDayBar], overflowByColumn: [Int: Int]) {
        var laneOccupancy: [[ClosedRange<Int>]] = []
        var bars: [AllDayBar] = []
        var overflowByColumn: [Int: Int] = [:]

        for candidate in candidates {
            let range = candidate.startColumn...candidate.endColumn
            // Find the lowest lane without a column conflict.
            var assignedLane: Int?
            for laneIndex in 0..<max(laneOccupancy.count, maxLanes) {
                let occupied = laneIndex < laneOccupancy.count ? laneOccupancy[laneIndex] : []
                if !occupied.contains(where: { $0.overlaps(range) }) {
                    assignedLane = laneIndex
                    break
                }
            }

            if let lane = assignedLane, lane < maxLanes {
                while laneOccupancy.count <= lane { laneOccupancy.append([]) }
                laneOccupancy[lane].append(range)
                bars.append(
                    AllDayBar(
                        item: candidate.item,
                        startColumn: candidate.startColumn,
                        endColumn: candidate.endColumn,
                        lane: lane,
                        clippedStart: candidate.clippedStart,
                        clippedEnd: candidate.clippedEnd
                    )
                )
            } else {
                for col in candidate.startColumn...candidate.endColumn {
                    overflowByColumn[col, default: 0] += 1
                }
            }
        }
        return (bars, overflowByColumn)
    }
}
