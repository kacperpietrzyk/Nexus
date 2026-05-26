import Foundation
import NexusCore

public struct TasksUpdateTool: AgentTool {
    public let name = "tasks.update"
    public let description = """
        Patch fields on an existing task. Omitted fields remain unchanged. Null
        clears nullable fields such as notes, due_date, and tags.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID to patch."),
            "patch": .object(
                properties: [
                    "title": .string(description: "Task title."),
                    "notes": .anyValue(description: "Task notes string, or null to clear."),
                    "due_string": .string(description: "Optional source due text; accepted but not persisted."),
                    "due_date": .anyValue(description: "ISO8601 due timestamp string, or null to clear."),
                    "deadline_date": .anyValue(
                        description: "YYYY-MM-DD hard external deadline string, or null to clear."
                    ),
                    "priority": .integer(
                        minimum: 1,
                        maximum: 4,
                        description: "Priority: 1 high, 2 medium, 3 low, 4 none/default."
                    ),
                    "tags": .anyValue(description: "Array of task tag strings, or null to clear."),
                    "project_id": .string(description: "Opaque project UUID; accepted but not persisted yet."),
                ],
                required: []
            ),
        ],
        required: ["task_id", "patch"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        guard let patch = args["patch"]?.objectValue else {
            throw AgentError.validation("patch must be an object")
        }

        let mutations = try TasksUpdatePatch.parse(patch)
        let task = try TasksMutationToolSupport.liveTask(id: id, context: context)
        try context.taskRepository.repository.update(task) { task in
            mutations.apply(to: task)
        }
        await TasksToolSearchIndexing.reflect(task, in: context.searchIndex)
        return try TasksToolJSON.encode(TaskDTO(from: task))
    }
}

private struct TasksUpdatePatch {
    let title: String??
    let notes: String??
    let dueDate: Date??
    let deadlineAt: Date??
    let priority: TaskPriority?
    let tags: [String]??

    static func parse(_ patch: [String: JSONValue]) throws -> Self {
        _ = try TasksStructuredCreateArguments.optionalString(patch["due_string"], field: "due_string")
        _ = try TasksStructuredCreateArguments.optionalProjectID(patch["project_id"])

        return Self(
            title: try nullableTitle(patch["title"]),
            notes: try nullableString(patch["notes"], field: "notes"),
            dueDate: try nullableDueDate(patch["due_date"]),
            deadlineAt: try nullableDeadlineAt(patch["deadline_date"]),
            priority: try optionalPriority(patch["priority"]),
            tags: try nullableTags(patch["tags"])
        )
    }

    @MainActor
    func apply(to task: TaskItem) {
        if let title {
            task.title = title ?? task.title
        }
        if let notes {
            task.body = notes ?? ""
        }
        if let dueDate {
            task.dueAt = dueDate
        }
        if let deadlineAt {
            task.deadlineAt = deadlineAt
        }
        if let priority {
            task.priorityRaw = priority.rawValue
        }
        if let tags {
            task.tags = tags ?? []
        }
    }

    private static func nullableTitle(_ value: JSONValue?) throws -> String?? {
        guard let value else { return nil }
        guard value != .null else {
            throw AgentError.validation("title cannot be null")
        }
        let title = try TasksStructuredCreateArguments.trimmedRequiredString(value, field: "title")
        return .some(title)
    }

    private static func nullableString(_ value: JSONValue?, field: String) throws -> String?? {
        guard let value else { return nil }
        if value == .null {
            return .some(nil)
        }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be a string or null")
        }
        return .some(text)
    }

    private static func nullableDueDate(_ value: JSONValue?) throws -> Date?? {
        guard let value else { return nil }
        if value == .null {
            return .some(nil)
        }
        return .some(try TasksMutationToolSupport.iso8601Date(value, field: "due_date"))
    }

    private static func nullableDeadlineAt(_ value: JSONValue?) throws -> Date?? {
        guard let value else { return nil }
        if value == .null {
            return .some(nil)
        }
        let date = try TasksStructuredCreateArguments.optionalDeadlineAt(value)
        return .some(date)
    }

    private static func optionalPriority(_ value: JSONValue?) throws -> TaskPriority? {
        guard value != nil else { return nil }
        return try TasksStructuredCreateArguments.optionalPriority(value)
    }

    private static func nullableTags(_ value: JSONValue?) throws -> [String]?? {
        guard let value else { return nil }
        if value == .null {
            return .some(nil)
        }
        return .some(try TasksStructuredCreateArguments.optionalTags(value))
    }
}
