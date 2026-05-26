import Foundation

/// Result returned by `WatchAgendaSelector.pick`. Splits the agenda into
/// active items (overdue + today) and recently-done items so the Watch UI can
/// render them in distinct sections.
public struct AgendaResult: Equatable, @unchecked Sendable {
    public let agenda: [TaskItem]
    public let recentlyDone: [TaskItem]

    public init(agenda: [TaskItem], recentlyDone: [TaskItem]) {
        self.agenda = agenda
        self.recentlyDone = recentlyDone
    }
}

/// Pure ranker fed by Watch agenda's filtered buckets. Overdue entries come
/// first sorted by due date, then today's entries sorted by due date.
/// Recently-done entries are sorted by `lastCompletedAt` descending and
/// returned in a separate bucket.
public enum WatchAgendaSelector {
    public static func pick(
        overdue: [TaskItem],
        today: [TaskItem],
        recentlyDone: [TaskItem] = [],
        now _: Date,
        maxAgenda: Int = 5,
        maxRecentlyDone: Int = 3
    ) -> AgendaResult {
        let overdueSorted = overdue.sorted {
            ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast)
        }
        let todaySorted = today.sorted {
            ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
        }
        let agenda = Array((overdueSorted + todaySorted).prefix(maxAgenda))

        let doneSorted =
            recentlyDone
            .compactMap { task -> (TaskItem, Date)? in
                guard let stamp = task.lastCompletedAt else { return nil }
                return (task, stamp)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxRecentlyDone)
            .map(\.0)

        return AgendaResult(agenda: agenda, recentlyDone: doneSorted)
    }
}
