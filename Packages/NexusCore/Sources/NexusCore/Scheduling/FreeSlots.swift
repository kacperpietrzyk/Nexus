import Foundation

/// A half-open free interval `[start, end)` available for scheduling.
public struct FreeSlot: Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A busy half-open interval `[start, end)` that obstructs scheduling.
struct BusyInterval: Equatable {
    var start: Date
    var end: Date
}

/// Pure free-slot computation (spec §6): the working window for a day minus
/// busy obstacles (events + accepted blocks), each padded by `bufferMinutes`,
/// with merged overlaps and sub-`minBlockMinutes` residual gaps discarded.
///
/// Deterministic and timezone-explicit: the working window is resolved from
/// `prefs.workdayStart`/`workdayEnd` against the injected `calendar` (never
/// `Calendar.current`).
enum FreeSlotComputer {
    /// Free slots within a single working day containing `dayStart`.
    static func freeSlots(
        forDayContaining dayAnchor: Date,
        events: [CalendarEvent],
        acceptedBlocks: [ScheduledBlock],
        prefs: CalendarPreferences,
        calendar: Calendar
    ) -> [FreeSlot] {
        guard
            let window = workingWindow(forDayContaining: dayAnchor, prefs: prefs, calendar: calendar)
        else {
            return []
        }
        let buffer = TimeInterval(prefs.bufferMinutes * 60)
        var obstacles: [BusyInterval] = []

        for event in events {
            obstacles.append(BusyInterval(start: event.start.addingTimeInterval(-buffer), end: event.end.addingTimeInterval(buffer)))
        }
        for block in acceptedBlocks where block.deletedAt == nil {
            obstacles.append(BusyInterval(start: block.start.addingTimeInterval(-buffer), end: block.end.addingTimeInterval(buffer)))
        }

        // Clip obstacles to the window and drop empties.
        let clipped: [BusyInterval] = obstacles.compactMap { obstacle in
            let start = max(obstacle.start, window.start)
            let end = min(obstacle.end, window.end)
            return start < end ? BusyInterval(start: start, end: end) : nil
        }

        let merged = mergeIntervals(clipped)
        let minSeconds = TimeInterval(prefs.minBlockMinutes * 60)

        var slots: [FreeSlot] = []
        var cursor = window.start
        for busy in merged {
            if busy.start.timeIntervalSince(cursor) >= minSeconds {
                slots.append(FreeSlot(start: cursor, end: busy.start))
            }
            cursor = max(cursor, busy.end)
        }
        if window.end.timeIntervalSince(cursor) >= minSeconds {
            slots.append(FreeSlot(start: cursor, end: window.end))
        }
        return slots
    }

    /// Resolve `workdayStart`/`workdayEnd` to an absolute `[start, end)` window
    /// for the day containing `dayAnchor`. Returns nil if the window is empty or
    /// the components cannot be resolved.
    static func workingWindow(
        forDayContaining dayAnchor: Date,
        prefs: CalendarPreferences,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let day = calendar.startOfDay(for: dayAnchor)
        guard
            let start = calendar.date(
                bySettingHour: prefs.workdayStart.hour ?? 9,
                minute: prefs.workdayStart.minute ?? 0,
                second: 0,
                of: day
            ),
            let end = calendar.date(
                bySettingHour: prefs.workdayEnd.hour ?? 18,
                minute: prefs.workdayEnd.minute ?? 0,
                second: 0,
                of: day
            ),
            start < end
        else {
            return nil
        }
        return (start, end)
    }

    /// Merge overlapping or adjacent intervals into a minimal sorted set.
    private static func mergeIntervals(_ intervals: [BusyInterval]) -> [BusyInterval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
        var merged: [BusyInterval] = [sorted[0]]
        for interval in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if interval.start <= last.end {
                merged[merged.count - 1] = BusyInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
