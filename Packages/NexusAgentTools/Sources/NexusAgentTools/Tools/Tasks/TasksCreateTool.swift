import Foundation
import NexusCore

public struct TasksCreateTool: AgentTool {
    public let name = "tasks.create"
    public let description =
        "Creates one structured task. For natural language input, use tasks.create_from_text."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "title": .string(description: "Task title."),
            "notes": .string(description: "Optional task notes."),
            "due_string": .string(description: "Optional source due text; due_date controls scheduling."),
            "due_date": .string(description: "Optional ISO8601 due timestamp."),
            "deadline_date": .string(
                description: "Optional YYYY-MM-DD hard external deadline (distinct from due date)."
            ),
            "priority": .integer(
                minimum: 1,
                maximum: 4,
                description: "Priority: 1 high, 2 medium, 3 low, 4 none/default."
            ),
            "tags": .array(items: .string(description: "Tag"), description: "Optional task tags."),
            "project_id": .string(description: "Project UUID to assign the task to."),
            "section_id": .string(description: "Section UUID within the project."),
            "parent_id": .string(description: "Parent task UUID for a subtask."),
            "recurrence_rule": .string(description: "RFC 5545 RRULE subset, e.g. FREQ=DAILY."),
            "reminders": .array(
                items: .object(
                    properties: [
                        "type": .string(description: "relative | absolute"),
                        "offset": .integer(
                            description: "relative: seconds before/after anchor (negative = before)"
                        ),
                        "anchor": .string(description: "relative: due | deadline"),
                        "at": .string(description: "absolute: ISO8601 timestamp"),
                    ],
                    required: ["type"]
                ),
                description: "Optional reminders."
            ),
        ],
        required: ["title"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let fields = try TasksStructuredCreateArguments.parse(args)
        let projectID = try TasksStructuredCreateArguments.optionalProjectID(args["project_id"])
        let sectionID = try TasksStructuredCreateArguments.optionalUUID(args["section_id"], field: "section_id")
        let parentID = try TasksStructuredCreateArguments.optionalUUID(args["parent_id"], field: "parent_id")
        let recurrence = try TasksStructuredCreateArguments.optionalRecurrenceRule(args["recurrence_rule"])
        let reminders = try TasksStructuredCreateArguments.optionalReminders(args["reminders"])

        let task = TaskItem(
            title: fields.title,
            body: fields.notes ?? "",
            dueAt: fields.dueDate,
            deadlineAt: fields.deadlineAt,
            priority: fields.priority,
            tags: fields.tags,
            recurrenceRule: recurrence,
            parentTaskID: parentID
        )
        task.reminders = reminders

        let repo = context.taskRepository.repository
        if let parentID {
            do {
                try repo.validateParentAssignment(taskID: task.id, proposedParentID: parentID)
            } catch {
                throw AgentError.validation("parent_id validation failed: \(error)")
            }
        }
        try repo.insert(task)
        if projectID != nil || sectionID != nil {
            do {
                try repo.assign(task, toProject: projectID, section: sectionID)
            } catch {
                throw AgentError.validation("project/section assignment failed: \(error)")
            }
        }
        await context.searchIndex.upsert(IndexedDocument(task))
        return try TasksToolJSON.encode(TaskDTO(from: task))
    }
}

enum TasksToolSearchIndexing {
    @MainActor
    static func reflect(_ task: TaskItem, in searchIndex: SearchIndex) async {
        if task.deletedAt == nil {
            await searchIndex.upsert(IndexedDocument(task))
        } else {
            await searchIndex.remove(kind: task.kind, id: task.id)
        }
    }
}

struct TasksStructuredCreateFields {
    let title: String
    let notes: String?
    let dueDate: Date?
    let deadlineAt: Date?
    let priority: TaskPriority
    let tags: [String]
}

enum TasksStructuredCreateArguments {
    static func parse(_ args: JSONValue) throws -> TasksStructuredCreateFields {
        let title = try trimmedRequiredString(args["title"], field: "title")
        let notes = try optionalString(args["notes"], field: "notes")
        _ = try optionalString(args["due_string"], field: "due_string")
        let deadlineAt = try optionalDeadlineAt(args["deadline_date"])
        let dueDate = try optionalDate(args["due_date"], field: "due_date")
        let priority = try optionalPriority(args["priority"])
        let tags = try optionalTags(args["tags"])
        return TasksStructuredCreateFields(
            title: title,
            notes: notes,
            dueDate: dueDate,
            deadlineAt: deadlineAt,
            priority: priority,
            tags: tags
        )
    }

    static func trimmedRequiredString(_ value: JSONValue?, field: String) throws -> String {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required string field: \(field)")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.validation("\(field) cannot be empty")
        }
        return trimmed
    }

    static func optionalString(_ value: JSONValue?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be a string")
        }
        return text
    }

    static func optionalDate(_ value: JSONValue?, field: String) throws -> Date? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be an ISO8601 string")
        }
        guard let date = parseISO8601(text) else {
            throw AgentError.validation("Invalid ISO8601 timestamp for field: \(field)")
        }
        return date
    }

    static func optionalDeadlineDate(_ value: JSONValue?) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("deadline_date must be a YYYY-MM-DD string")
        }
        guard isValidDateOnly(text) else {
            throw AgentError.validation("deadline_date must be a valid YYYY-MM-DD date")
        }
        return text
    }

    /// Parses the optional `deadline_date` field into a `Date` anchored at
    /// start-of-day in the device's current calendar so the value round-trips
    /// through `TaskDTO.deadlineDateString` on the same machine. Returns `nil`
    /// when the field is omitted.
    static func optionalDeadlineAt(_ value: JSONValue?) throws -> Date? {
        guard let text = try optionalDeadlineDate(value) else { return nil }
        return parseDeadlineDate(text)
    }

    static func parseDeadlineDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = TaskDTO.currentDeadlineCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TaskDTO.currentDeadlineCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: text)
    }

    static func optionalProjectID(_ value: JSONValue?) throws -> UUID? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("project_id must be a UUID string")
        }
        guard let id = UUID(uuidString: text) else {
            throw AgentError.validation("project_id must be a valid UUID")
        }
        return id
    }

    static func optionalUUID(_ value: JSONValue?, field: String) throws -> UUID? {
        guard let value else { return nil }
        guard let text = value.stringValue, let id = UUID(uuidString: text) else {
            throw AgentError.validation("\(field) must be a valid UUID")
        }
        return id
    }

    static func optionalRecurrenceRule(_ value: JSONValue?) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("recurrence_rule must be a string")
        }
        do {
            _ = try RRuleParser.parse(text)
        } catch {
            throw AgentError.validation("recurrence_rule is not a valid RRULE: \(text)")
        }
        return text
    }

    static func optionalReminders(_ value: JSONValue?) throws -> [ReminderRule] {
        guard let value else { return [] }
        guard value.arrayValue != nil else {
            throw AgentError.validation("reminders must be an array")
        }
        let data = try JSONEncoder().encode(value)
        let dtos = try JSONDecoder().decode([ReminderDTO].self, from: data)
        return try dtos.map { dto in
            guard let rule = dto.toRule() else {
                throw AgentError.validation("invalid reminder entry")
            }
            return rule
        }
    }

    static func optionalPriority(_ value: JSONValue?) throws -> TaskPriority {
        guard let value else { return .none }
        guard let intValue = value.intValue else {
            throw AgentError.validation("priority must be an integer from 1 to 4")
        }
        switch intValue {
        case 1: return .high
        case 2: return .medium
        case 3: return .low
        case 4: return .none
        default:
            throw AgentError.validation("priority must be an integer from 1 to 4")
        }
    }

    static func optionalTags(_ value: JSONValue?) throws -> [String] {
        guard let value else { return [] }
        guard let values = value.arrayValue else {
            throw AgentError.validation("tags must be an array of strings")
        }
        return try values.enumerated().map { index, value in
            guard let tag = value.stringValue else {
                throw AgentError.validation("tags[\(index)] must be a string")
            }
            return tag
        }
    }

    private static func parseISO8601(_ text: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: text) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func isValidDateOnly(_ text: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text) else { return false }
        return formatter.string(from: date) == text
    }
}
