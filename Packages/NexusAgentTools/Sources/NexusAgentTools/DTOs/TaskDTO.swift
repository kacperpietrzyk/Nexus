import Foundation
import NexusCore

/// Wire format for `TaskItem` exposed via MCP. snake_case keys per MCP convention.
public struct TaskDTO: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let notes: String?
    public let dueDate: String?
    public let deadlineDate: String?
    public let priority: Int
    public let tags: [String]
    public let projectID: String?
    public let state: String
    public let snoozeUntil: String?
    public let externalSourceID: String?
    public let recurrenceRule: String?
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, priority, tags, state
        case dueDate = "due_date"
        case deadlineDate = "deadline_date"
        case projectID = "project_id"
        case snoozeUntil = "snooze_until"
        case externalSourceID = "external_source_id"
        case recurrenceRule = "recurrence_rule"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        title: String,
        notes: String?,
        dueDate: String?,
        deadlineDate: String?,
        priority: Int,
        tags: [String],
        projectID: String?,
        state: String,
        snoozeUntil: String?,
        externalSourceID: String?,
        recurrenceRule: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.deadlineDate = deadlineDate
        self.priority = priority
        self.tags = tags
        self.projectID = projectID
        self.state = state
        self.snoozeUntil = snoozeUntil
        self.externalSourceID = externalSourceID
        self.recurrenceRule = recurrenceRule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    @MainActor
    public init(from task: TaskItem) {
        self.init(from: task, deadlineCalendar: Self.currentDeadlineCalendar)
    }

    @MainActor
    internal init(from task: TaskItem, deadlineCalendar: Calendar) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.init(
            id: task.id.uuidString,
            title: task.title,
            notes: task.body.isEmpty ? nil : task.body,
            dueDate: task.dueAt.map { formatter.string(from: $0) },
            deadlineDate: task.deadlineAt.map { Self.deadlineDateString(for: $0, calendar: deadlineCalendar) },
            priority: Self.priorityToInt(task.priority),
            tags: task.tags,
            projectID: nil,
            state: Self.stateString(for: task),
            snoozeUntil: task.snoozedUntil.map { formatter.string(from: $0) },
            externalSourceID: task.externalSourceID,
            recurrenceRule: task.recurrenceRule,
            createdAt: formatter.string(from: task.createdAt),
            updatedAt: formatter.string(from: task.updatedAt)
        )
    }

    internal static func deadlineDateString(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Calendar used for `deadline_date` round-trips on both encode and decode.
    /// ISO-8601 calendar with the current device timezone so that a parsed
    /// "YYYY-MM-DD" survives `parse -> store -> render` on the same machine.
    internal static var currentDeadlineCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    private static func priorityToInt(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        case .none: return 4
        }
    }

    private static func stateString(for task: TaskItem) -> String {
        if task.deletedAt != nil { return "deleted" }
        switch task.status {
        case .done: return "done"
        case .open, .snoozed: return "open"
        }
    }
}
