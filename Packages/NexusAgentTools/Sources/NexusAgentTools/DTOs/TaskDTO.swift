import Foundation
import NexusCore
import SwiftData

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
    public let sectionID: String?
    public let parentID: String?
    public let state: String
    /// Projects-tier optional tracker state (`backlog`/`todo`/`inProgress`/`inReview`/
    /// `done`/`canceled`/`duplicate`). `nil` = a plain GTD task not on the machine
    /// (spec §4.2). Additive: `state` (open/done) stays the canonical truth (I7).
    public let workflowState: String?
    /// Projects-tier agent assignment (`codex`/`claude`). `nil` = self (spec §4.5).
    public let assignedAgent: String?
    public let snoozeUntil: String?
    public let externalSourceID: String?
    public let recurrenceRule: String?
    public let reminders: [ReminderDTO]?
    public let createdAt: String
    public let updatedAt: String
    /// Cycle assignment (Tranche 2 Plan C). Additive, appended last so existing
    /// positional callers keep compiling.
    public let cycleID: String?
    /// User-owned duration estimate in seconds (Calendar / Motion-AI module,
    /// spec §4.2). `nil` = no estimate. Canonical unit is seconds (lossless —
    /// `CalendarSyncReconciler` may write non-minute-aligned values); the
    /// create/update tools accept minutes and convert. Appended last so existing
    /// positional callers keep compiling.
    public let estimatedDurationSeconds: Int?
    /// Dedicated event date for inbox/timeline chronology (issue #9), distinct
    /// from `createdAt` (record creation). `nil` when unset — emitted RAW, NOT
    /// coalesced; the `occurredAt ?? createdAt` fallback lives only in MCP
    /// read/sort paths. Appended last so existing positional callers keep compiling.
    public let occurredAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, priority, tags, state, reminders
        case dueDate = "due_date"
        case deadlineDate = "deadline_date"
        case projectID = "project_id"
        case sectionID = "section_id"
        case parentID = "parent_id"
        case workflowState = "workflow_state"
        case assignedAgent = "assigned_agent"
        case snoozeUntil = "snooze_until"
        case externalSourceID = "external_source_id"
        case recurrenceRule = "recurrence_rule"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case cycleID = "cycle_id"
        case estimatedDurationSeconds = "estimated_duration_seconds"
        case occurredAt = "occurred_at"
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
        sectionID: String?,
        parentID: String?,
        state: String,
        workflowState: String?,
        assignedAgent: String?,
        snoozeUntil: String?,
        externalSourceID: String?,
        recurrenceRule: String?,
        reminders: [ReminderDTO]?,
        createdAt: String,
        updatedAt: String,
        cycleID: String? = nil,
        estimatedDurationSeconds: Int? = nil,
        occurredAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.deadlineDate = deadlineDate
        self.priority = priority
        self.tags = tags
        self.projectID = projectID
        self.sectionID = sectionID
        self.parentID = parentID
        self.state = state
        self.workflowState = workflowState
        self.assignedAgent = assignedAgent
        self.snoozeUntil = snoozeUntil
        self.externalSourceID = externalSourceID
        self.recurrenceRule = recurrenceRule
        self.reminders = reminders
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cycleID = cycleID
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.occurredAt = occurredAt
    }

    @MainActor
    public init(from task: TaskItem) {
        self.init(from: task, deadlineCalendar: Self.currentDeadlineCalendar)
    }

    @MainActor
    internal init(from task: TaskItem, deadlineCalendar: Calendar) {
        self.init(
            from: task,
            deadlineCalendar: deadlineCalendar,
            notes: task.body.isEmpty ? nil : task.body
        )
    }

    @MainActor
    public init(from task: TaskItem, modelContext: ModelContext) throws {
        self.init(
            from: task,
            deadlineCalendar: Self.currentDeadlineCalendar,
            notes: try Self.notes(for: task, modelContext: modelContext)
        )
    }

    @MainActor
    internal init(from task: TaskItem, deadlineCalendar: Calendar, notes: String?) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.init(
            id: task.id.uuidString,
            title: task.title,
            notes: notes,
            dueDate: task.dueAt.map { formatter.string(from: $0) },
            deadlineDate: task.deadlineAt.map { Self.deadlineDateString(for: $0, calendar: deadlineCalendar) },
            priority: Self.priorityToInt(task.priority),
            tags: task.tags,
            projectID: task.projectID?.uuidString,
            sectionID: task.sectionID?.uuidString,
            parentID: task.parentTaskID?.uuidString,
            state: Self.stateString(for: task),
            workflowState: task.workflowState?.rawValue,
            assignedAgent: task.assignedAgent,
            snoozeUntil: task.snoozedUntil.map { formatter.string(from: $0) },
            externalSourceID: task.externalSourceID,
            recurrenceRule: task.recurrenceRule,
            reminders: task.reminders.isEmpty ? nil : task.reminders.map { ReminderDTO.from($0, formatter: formatter) },
            createdAt: formatter.string(from: task.createdAt),
            updatedAt: formatter.string(from: task.updatedAt),
            cycleID: task.cycleID?.uuidString,
            estimatedDurationSeconds: task.estimatedDurationSeconds,
            // Raw, NOT coalesced — nil when unset. The occurredAt ?? createdAt
            // fallback lives only in the MCP read/sort path (TasksListTool).
            occurredAt: task.occurredAt.map { formatter.string(from: $0) }
        )
    }

    @MainActor
    private static func notes(for task: TaskItem, modelContext: ModelContext) throws -> String? {
        let markdown = try TaskNoteContent.markdown(for: task, in: modelContext)
        return markdown.isEmpty ? nil : markdown
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

/// Wire shape for a single `ReminderRule`. Used in `TaskDTO.reminders`.
public struct ReminderDTO: Codable, Sendable, Equatable {
    /// "relative" or "absolute"
    public let type: String
    /// Relative only: seconds before (negative) or after the anchor.
    public let offset: TimeInterval?
    /// Relative only: "due" or "deadline".
    public let anchor: String?
    /// Absolute only: ISO8601 date string.
    public let at: String?
    /// Absolute only: "daily" or "weekly" (`ReminderRepeat` raw value). nil = one-shot.
    public let repeatFrequency: String?

    private enum CodingKeys: String, CodingKey {
        case type, offset, anchor, at
        case repeatFrequency = "repeat"
    }

    @MainActor
    static func from(_ rule: ReminderRule, formatter: ISO8601DateFormatter) -> ReminderDTO {
        switch rule {
        case .relative(let offset, let anchor):
            return ReminderDTO(type: "relative", offset: offset, anchor: anchor.rawValue, at: nil, repeatFrequency: nil)
        case .absolute(let date, let repeats):
            return ReminderDTO(
                type: "absolute", offset: nil, anchor: nil,
                at: formatter.string(from: date), repeatFrequency: repeats?.rawValue
            )
        }
    }

    func toRule() -> ReminderRule? {
        switch type {
        case "relative":
            guard let offset, let anchorRaw = anchor, let anchor = ReminderAnchor(rawValue: anchorRaw) else { return nil }
            return .relative(offset: offset, anchor: anchor)
        case "absolute":
            guard let at else { return nil }
            let repeats: ReminderRepeat?
            if let repeatFrequency {
                guard let parsed = ReminderRepeat(rawValue: repeatFrequency) else { return nil }
                repeats = parsed
            } else {
                repeats = nil
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: at) { return .absolute(at: date, repeats: repeats) }
            if let date = ISO8601DateFormatter().date(from: at) { return .absolute(at: date, repeats: repeats) }
            return nil
        default:
            return nil
        }
    }
}
