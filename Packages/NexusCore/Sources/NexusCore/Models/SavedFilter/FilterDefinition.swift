import Foundation

public indirect enum FilterDefinition: Codable, Sendable, Equatable {
    case unsorted
    case dueWithin(days: Int)
    case overdue
    case byTag(String)
    case byProject(UUID)
    case bySection(UUID)
    case priorityAtLeast(TaskPriority)
    case withDeadlineWithin(days: Int)
    case and([FilterDefinition])
    case or([FilterDefinition])
    case not(FilterDefinition)
}

extension FilterDefinition {
    /// Pure-Swift matcher used by tests and by repositories that hydrate then filter.
    /// Saved filters are active-task lists: soft-deleted, done, and snoozed tasks
    /// never match, including through boolean composition.
    /// Repository paths hydrate active candidates and apply this matcher in memory.
    public func matches(_ task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard task.deletedAt == nil, task.status == .open else {
            return false
        }
        switch self {
        case .unsorted:
            return task.projectID == nil && task.dueAt == nil
        case .dueWithin(let days):
            guard let due = task.dueAt else { return false }
            let limit = calendar.date(byAdding: .day, value: days, to: now) ?? now
            return due <= limit && due >= calendar.startOfDay(for: now)
        case .overdue:
            guard let due = task.dueAt else { return false }
            return due < now
        case .byTag(let tag):
            let normalizedTag = Self.normalize(tag: tag)
            return task.tags.contains { Self.normalize(tag: $0) == normalizedTag }
        case .byProject(let id):
            return task.projectID == id
        case .bySection(let id):
            return task.sectionID == id
        case .priorityAtLeast(let priority):
            return task.priority.rawValue >= priority.rawValue
        case .withDeadlineWithin(let days):
            guard let deadline = task.deadlineAt else { return false }
            let limit = calendar.date(byAdding: .day, value: days, to: now) ?? now
            return deadline <= limit
        case .and(let definitions):
            return definitions.allSatisfy { $0.matches(task, now: now, calendar: calendar) }
        case .or(let definitions):
            return definitions.contains { $0.matches(task, now: now, calendar: calendar) }
        case .not(let definition):
            return !definition.matches(task, now: now, calendar: calendar)
        }
    }

    private static func normalize(tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
