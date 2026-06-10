import Foundation
import NexusCore

/// Pure derived-data service for the liquid-glass Calendar surfaces (Week /
/// Today): event conflicts, meeting load, suggested focus blocks, and weekly
/// time insights — all computed from `[CalendarEvent]` already fetched by the
/// view-model. No SwiftData, no EventKit, no ambient clock; every function is
/// deterministic over its inputs.
///
/// Reuse note: NexusCore's `FreeSlotComputer` (the DayPlanner/DayScheduler gap
/// engine) is internal to NexusCore and is shaped around `CalendarPreferences`
/// (workday `DateComponents`, buffer padding, min-block pruning) plus `@Model
/// ScheduledBlock` obstacles. The gap semantics needed here (explicit
/// `DateInterval` window, no buffers, plain minimum duration) differ, so the
/// interval merge/gap walk is implemented locally instead of widening
/// NexusCore's API.
public enum SchedulingIntelligence {
    /// Two non-all-day events whose time ranges genuinely overlap, plus the
    /// overlapping interval. `first` starts no later than `second` (ties broken
    /// by end, then id), and each unordered pair is reported once.
    public struct EventConflict: Equatable, Sendable, Identifiable {
        public let first: CalendarEvent
        public let second: CalendarEvent
        public let overlap: DateInterval

        /// Stable composite id: pairs are deterministically ordered and each
        /// unordered pair is reported once, so this is unique per conflict.
        public var id: String { "\(first.id)|\(second.id)" }

        public init(first: CalendarEvent, second: CalendarEvent, overlap: DateInterval) {
            self.first = first
            self.second = second
            self.overlap = overlap
        }
    }

    /// All pairs of non-all-day events whose ranges overlap with duration > 0
    /// (touching boundaries are not conflicts). Pairs are ordered by the first
    /// event's start, deterministically.
    public static func conflicts(in events: [CalendarEvent]) -> [EventConflict] {
        let timed = events.filter { !$0.isAllDay }.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            return lhs.id < rhs.id
        }

        var conflicts: [EventConflict] = []
        for (index, first) in timed.enumerated() {
            for second in timed.dropFirst(index + 1) {
                // Sweep-line cutoff only: events are sorted by start, so once
                // `second` starts at/after `first.end`, no later event can
                // overlap `first`. This does NOT filter zero-duration overlaps —
                // the `overlapStart < overlapEnd` guard below is the real
                // strict-overlap filter (e.g. zero-length `first`); keep both.
                guard second.start < first.end else { break }
                let overlapStart = max(first.start, second.start)
                let overlapEnd = min(first.end, second.end)
                guard overlapStart < overlapEnd else { continue }
                conflicts.append(
                    EventConflict(
                        first: first,
                        second: second,
                        overlap: DateInterval(start: overlapStart, end: overlapEnd)
                    )
                )
            }
        }
        return conflicts
    }

    /// Fraction `[0, 1]` of `workday` covered by events the caller classifies
    /// as meetings. Overlapping meetings are unioned (never double-counted) and
    /// clipped to the workday; all-day events are ignored. A degenerate
    /// (zero-length) workday yields 0.
    public static func meetingLoad(
        events: [CalendarEvent],
        workday: DateInterval,
        isMeeting: (CalendarEvent) -> Bool
    ) -> Double {
        guard workday.duration > 0 else { return 0 }
        let meetings = events.filter { !$0.isAllDay && isMeeting($0) }
        let covered = unionDuration(of: meetings.compactMap { clip($0, to: workday) })
        return min(1, covered / workday.duration)
    }

    /// Maximal free gaps of at least `minimumDuration` between non-all-day
    /// events inside `workday`, sorted by start. A gap exactly equal to the
    /// minimum is included. Overlapping events merge into one busy span; events
    /// outside the window (and zero-length ones) never split a gap.
    ///
    /// Implemented locally rather than via NexusCore's `FreeSlotComputer` — see
    /// the type-level reuse note.
    public static func suggestedFocusBlocks(
        events: [CalendarEvent],
        within workday: DateInterval,
        minimumDuration: TimeInterval = 3600
    ) -> [DateInterval] {
        let busy = mergedIntervals(events.compactMap { clip($0, to: workday) })

        var gaps: [DateInterval] = []
        var cursor = workday.start
        for span in busy {
            if span.start.timeIntervalSince(cursor) >= minimumDuration {
                gaps.append(DateInterval(start: cursor, end: span.start))
            }
            cursor = max(cursor, span.end)
        }
        if workday.end.timeIntervalSince(cursor) >= minimumDuration {
            gaps.append(DateInterval(start: cursor, end: workday.end))
        }
        return gaps
    }

    /// How an event spends time, for weekly insights. Mirrors the semantics of
    /// NexusUI's `LiquidEventKind` (focus/meeting/project/personal/admin) plus
    /// `other`, without importing NexusUI into this UI-free service; the view
    /// layer maps categories to its kinds.
    public enum EventCategory: Hashable, Sendable, CaseIterable {
        case meeting
        case focus
        case project
        case personal
        case admin
        case other
    }

    /// Weekly time totals. Per-category totals sum each event's clipped
    /// duration independently, so concurrently scheduled events of different
    /// categories both count toward their own category; `totalScheduled` is
    /// the union of all scheduled time and therefore never double-counts.
    public struct TimeInsights: Equatable, Sendable {
        /// Seconds per category (clipped to the week; categories with no
        /// events are absent).
        public let totals: [EventCategory: TimeInterval]
        /// Union of all scheduled (non-all-day) time within the week.
        public let totalScheduled: TimeInterval

        public init(totals: [EventCategory: TimeInterval], totalScheduled: TimeInterval) {
            self.totals = totals
            self.totalScheduled = totalScheduled
        }

        /// Total seconds for `category` (0 when nothing was scheduled).
        public func total(for category: EventCategory) -> TimeInterval {
            totals[category] ?? 0
        }
    }

    /// Per-category time totals plus the unioned total for non-all-day events
    /// clipped to `week`. See `TimeInsights` for the overlap semantics.
    public static func timeInsights(
        events: [CalendarEvent],
        week: DateInterval,
        classify: (CalendarEvent) -> EventCategory
    ) -> TimeInsights {
        var totals: [EventCategory: TimeInterval] = [:]
        var scheduled: [DateInterval] = []
        for event in events {
            guard let interval = clip(event, to: week) else { continue }
            totals[classify(event), default: 0] += interval.duration
            scheduled.append(interval)
        }
        return TimeInsights(totals: totals, totalScheduled: unionDuration(of: scheduled))
    }

    // MARK: - Interval helpers

    /// The event's range clipped to `window`, or nil when all-day, outside the
    /// window, or empty after clipping.
    private static func clip(_ event: CalendarEvent, to window: DateInterval) -> DateInterval? {
        guard !event.isAllDay else { return nil }
        let start = max(event.start, window.start)
        let end = min(event.end, window.end)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Total duration of the union of `intervals` (overlaps counted once).
    private static func unionDuration(of intervals: [DateInterval]) -> TimeInterval {
        mergedIntervals(intervals).reduce(0) { $0 + $1.duration }
    }

    /// Merge overlapping or touching intervals into a minimal sorted set.
    private static func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
