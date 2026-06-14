import Foundation

/// Pure rule-based free-slot finder. No model. Lives in NexusCore alongside DeadlineRiskAnalyzer.
/// Named SlotScheduler to distinguish from the existing job-scheduling `Scheduler` actor in NexusCore.
public struct SlotScheduler: Sendable {
    public let calendar: Calendar
    public init(calendar: Calendar = .current) { self.calendar = calendar }

    /// Free gaps inside `workday`, each ≥ minimumMinutes, chunked to ≤ maximumMinutes.
    public func freeSlots(
        events: [CalendarEvent], within workday: DateInterval,
        minimumMinutes: Int, maximumMinutes: Int
    ) -> [DateInterval] {
        let minSec = TimeInterval(minimumMinutes * 60)
        let maxSec = maximumMinutes <= 0 ? TimeInterval.infinity : TimeInterval(maximumMinutes * 60)
        // Busy spans clipped to the workday, merged.
        // Pre-filter to only events that actually overlap the workday window before clipping
        // (prevents end < start in DateInterval when an event ends before the window starts).
        let busy =
            events
            .filter { !$0.isAllDay && $0.start < workday.end && $0.end > workday.start }
            .map { DateInterval(start: max($0.start, workday.start), end: min($0.end, workday.end)) }
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for span in busy {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
            } else {
                merged.append(span)
            }
        }
        // Gaps between merged busy spans.
        var gaps: [DateInterval] = []
        var cursor = workday.start
        for span in merged {
            if span.start > cursor { gaps.append(DateInterval(start: cursor, end: span.start)) }
            cursor = max(cursor, span.end)
        }
        if cursor < workday.end { gaps.append(DateInterval(start: cursor, end: workday.end)) }
        // Chunk to max, keep chunks ≥ min.
        var result: [DateInterval] = []
        for gap in gaps {
            var start = gap.start
            while gap.end.timeIntervalSince(start) >= minSec {
                let chunkEnd = min(gap.end, start.addingTimeInterval(maxSec))
                result.append(DateInterval(start: start, end: chunkEnd))
                start = chunkEnd
            }
        }
        return result
    }

    /// First slot of `durationMinutes` at/after `after`, scanning workday windows across `days`.
    public func slot(
        durationMinutes: Int, within days: [Date], events: [CalendarEvent],
        prefs: CalendarPreferences, after: Date
    ) -> DateInterval? {
        let needSec = TimeInterval(durationMinutes * 60)
        for rawDay in days.sorted() {
            guard let window = workdayWindow(for: rawDay, prefs: prefs) else { continue }
            let clamped = DateInterval(start: max(window.start, after), end: window.end)
            guard clamped.duration >= needSec else { continue }
            let free = freeSlots(
                events: events, within: clamped,
                minimumMinutes: durationMinutes, maximumMinutes: 0)
            if let first = free.first(where: { $0.duration >= needSec }) {
                return DateInterval(start: first.start, duration: needSec)
            }
        }
        return nil
    }

    private func workdayWindow(for day: Date, prefs: CalendarPreferences) -> DateInterval? {
        let sod = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: prefs.workdayStart, to: sod),
            let end = calendar.date(byAdding: prefs.workdayEnd, to: sod), end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }
}
