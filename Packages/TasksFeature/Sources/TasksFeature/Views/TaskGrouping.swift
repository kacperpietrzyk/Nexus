import Foundation
import NexusCore

/// User-selectable sectioning for the flat task filters (`.all`/`.upcoming`/
/// `.inbox`). `.none` keeps the current flat list verbatim. Persisted across
/// launches via `NexusPreferences.Keys.taskListGroupBy`. Orthogonal to the
/// `.today` semantic buckets, which are unaffected.
public enum TaskGroupBy: String, CaseIterable, Sendable {
    case none
    case project
    case date
    case priority

    public var title: String {
        switch self {
        case .none: return "Group"
        case .project: return "Project"
        case .date: return "Date"
        case .priority: return "Priority"
        }
    }
}

/// Sections the already-fetched flat list for display. Pure: `now`/`calendar`
/// injected like `DueChipFormatter`. Empty groups are omitted (matches the
/// list's `section(_:items:)` behavior). `.none` returns a single anonymous
/// group so callers render the flat list unchanged.
@MainActor
func taskGroupSections(
    _ items: [TaskItem],
    by groupBy: TaskGroupBy,
    projectsByID: [UUID: Project],
    now: Date,
    calendar: Calendar
) -> [(key: String, items: [TaskItem])] {
    switch groupBy {
    case .none:
        return [("", items)]

    case .priority:
        let order: [(String, TaskPriority)] = [("High", .high), ("Med", .medium), ("Low", .low), ("None", .none)]
        return order.compactMap { title, p in
            let group = items.filter { $0.priority == p }
            return group.isEmpty ? nil : (title, group)
        }

    case .date:
        let order = ["Overdue", "Today", "Tomorrow", "This week", "Later", "No date"]
        var buckets: [String: [TaskItem]] = [:]
        for item in items {
            buckets[dateBucketKey(for: item, now: now, calendar: calendar), default: []].append(item)
        }
        return order.compactMap { key in
            guard let group = buckets[key], !group.isEmpty else { return nil }
            return (key, group)
        }

    case .project:
        var buckets: [UUID: [TaskItem]] = [:]
        var orphans: [TaskItem] = []
        for item in items {
            if let pid = item.projectID, projectsByID[pid] != nil {
                buckets[pid, default: []].append(item)
            } else {
                orphans.append(item)
            }
        }
        // Stable order: by project name (case-insensitive), then "No project".
        var sections = buckets.keys
            .compactMap { pid -> (key: String, items: [TaskItem])? in
                guard let name = projectsByID[pid]?.name, let group = buckets[pid] else { return nil }
                return (name, group)
            }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        if !orphans.isEmpty { sections.append((key: "No project", items: orphans)) }
        return sections
    }
}

/// Maps a task's due date to a date-grouping bucket key. Reuses
/// `DueChipFormatter` boundaries so list grouping and the row chip never drift.
@MainActor
private func dateBucketKey(for item: TaskItem, now: Date, calendar: Calendar) -> String {
    switch DueChipFormatter.label(for: item, now: now, calendar: calendar) {
    case .noDate: return "No date"
    case .overdue: return "Overdue"
    case .today: return "Today"
    case .tomorrow: return "Tomorrow"
    case .future:
        // Within 7 days of today → "This week", else "Later".
        guard let due = item.dueAt else { return "Later" }
        let startToday = calendar.startOfDay(for: now)
        let startDue = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: startToday, to: startDue).day ?? 99
        return days <= 7 ? "This week" : "Later"
    }
}
