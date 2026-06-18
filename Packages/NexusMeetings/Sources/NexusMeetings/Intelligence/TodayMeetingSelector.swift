import Foundation

/// Pure selector that picks the best meeting to show in the Meeting Intelligence
/// card on the Today dashboard.
///
/// Priority:
/// 1. Pinned — the most recently pinned (`pinnedAt` desc).
/// 2. Today — started within the same calendar day as `now`, most recent.
/// 3. Fallback — the most-recently-started processed meeting.
///
/// `candidates` must already be pre-filtered to processed, non-deleted meetings.
public enum TodayMeetingSelector {
    /// Selects the best meeting from `candidates`.
    /// - Parameters:
    ///   - candidates: Processed, non-deleted meetings the caller fetched.
    ///   - now: The reference instant (injectable for deterministic tests).
    ///   - calendar: Calendar used for same-day comparison (defaults to `.current`).
    /// - Returns: The highest-priority meeting, or `nil` if `candidates` is empty.
    public static func select(
        _ candidates: [Meeting],
        now: Date,
        calendar: Calendar = .current
    ) -> Meeting? {
        // Branch 1: pinned — pick the one pinned most recently.
        let pinned = candidates.filter { $0.isPinned }
        if let best = pinned.max(by: { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }) {
            return best
        }

        // Branch 2: started today — pick the one that started most recently today.
        let todayMeetings = candidates.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
        if let best = todayMeetings.max(by: { $0.startedAt < $1.startedAt }) {
            return best
        }

        // Branch 3: fallback — most-recently-started processed meeting.
        return candidates.max(by: { $0.startedAt < $1.startedAt })
    }
}
