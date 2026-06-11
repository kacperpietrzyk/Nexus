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
                    "notes": .anyOf(
                        [.string(description: "Task notes."), .null(description: "Clear task notes.")],
                        description: "Task notes string, or null to clear."
                    ),
                    "due_string": .string(description: "Optional source due text; accepted but not persisted."),
                    "due_date": .anyOf(
                        [.string(description: "ISO8601 due timestamp."), .null(description: "Clear due date.")],
                        description: "ISO8601 due timestamp string, or null to clear."
                    ),
                    "deadline_date": .anyOf(
                        [.string(description: "YYYY-MM-DD hard external deadline."), .null(description: "Clear deadline.")],
                        description: "YYYY-MM-DD hard external deadline string, or null to clear."
                    ),
                    "priority": .integer(
                        minimum: 1,
                        maximum: 4,
                        description: "Priority: 1 high, 2 medium, 3 low, 4 none/default."
                    ),
                    "tags": .anyOf(
                        [.array(items: .string(description: "Tag")), .null(description: "Clear tags.")],
                        description: "Array of task tag strings, or null to clear."
                    ),
                    "project_id": .anyOf(
                        [.string(description: "Project UUID."), .null(description: "Clear project and section.")],
                        description: "Project UUID; null to clear."
                    ),
                    "section_id": .anyOf(
                        [.string(description: "Section UUID within the project."), .null(description: "Clear section.")],
                        description: "Section UUID within the project; null to clear."
                    ),
                    "parent_id": .anyOf(
                        [.string(description: "Parent task UUID for a subtask."), .null(description: "Clear parent.")],
                        description: "Parent task UUID for a subtask; null to clear."
                    ),
                    "recurrence_rule": .anyOf(
                        [.string(description: "RFC 5545 RRULE subset, e.g. FREQ=DAILY."), .null(description: "Clear recurrence.")],
                        description: "RFC 5545 RRULE subset, e.g. FREQ=DAILY; null to clear."
                    ),
                    "reminders": .anyOf(
                        [
                            .array(
                                items: .object(
                                    properties: [
                                        "type": .string(
                                            enumValues: ["relative", "absolute"],
                                            description: "relative | absolute"
                                        ),
                                        "offset": .integer(
                                            description: "relative: seconds before/after anchor (negative = before)"
                                        ),
                                        "anchor": .string(
                                            enumValues: ["due", "deadline"],
                                            description: "relative: due | deadline"
                                        ),
                                        "at": .string(description: "absolute: ISO8601 timestamp"),
                                    ],
                                    required: ["type"]
                                )
                            ),
                            .null(description: "Clear all reminders."),
                        ],
                        description: "Array of reminder objects, or null to clear."
                    ),
                    "cycle_id": .anyOf(
                        [.string(description: "Cycle UUID."), .null(description: "Clear the cycle assignment.")],
                        description: "Cycle UUID; null to clear. Applied via the cycle-assignment write path."
                    ),
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
        // Validate parent assignment before entering the non-throwing update closure.
        // mutations.parentID is UUID?? — only validate when a non-nil UUID is proposed.
        if let outerParentID = mutations.parentID, let proposedParentID = outerParentID {
            do {
                try context.taskRepository.repository.validateParentAssignment(
                    taskID: task.id, proposedParentID: proposedParentID
                )
            } catch {
                throw AgentError.validation("parent_id validation failed: \(error)")
            }
        }
        let assignment = try assignmentIfNeeded(
            patch: patch,
            task: task,
            parentID: mutations.parentID,
            context: context
        )
        try context.taskRepository.repository.update(task) { task in
            mutations.apply(to: task)
        }
        if let notes = mutations.notes {
            try TaskNotesContentStore.replaceNotes(notes, for: task, context: context)
        }

        // project/section assignment must happen after repo.update (needs repo.assign, not the closure).
        // repo.assign sets BOTH projectID and sectionID unconditionally, so we use effective-value
        // resolution: an omitted arg falls back to the task's existing value rather than clobbering it.
        // A present null clears the field; a present UUID string sets it; absent preserves existing.
        if let assignment {
            do {
                try context.taskRepository.repository.assign(
                    task, toProject: assignment.projectID, section: assignment.sectionID
                )
            } catch {
                throw AgentError.validation("project/section assignment failed: \(error)")
            }
        }

        // cycle_id routes through assignCycle (NOT the mutations closure) so the
        // cycleChanged activity event records exactly once with validation.
        if let cycleValue = patch["cycle_id"] {
            let cycleID: UUID?
            if cycleValue == .null {
                cycleID = nil
            } else {
                cycleID = try TasksToolArguments.requiredUUID(cycleValue, field: "cycle_id")
            }
            do {
                try context.taskRepository.repository.assignCycle(task, to: cycleID)
            } catch let error as TaskItemRepositoryError {
                throw AgentError.validation("cycle assignment failed: \(error)")
            }
        }

        await TasksToolSearchIndexing.reflect(task, in: context.searchIndex)
        return try TasksToolJSON.encode(TaskNotesContentStore.dto(for: task, context: context))
    }

    @MainActor
    private func assignmentIfNeeded(
        patch: [String: JSONValue],
        task: TaskItem,
        parentID: UUID??,
        context: AgentContext
    ) throws -> (projectID: UUID?, sectionID: UUID?)? {
        let hasProject = patch["project_id"] != nil
        let hasSection = patch["section_id"] != nil
        let repo = context.taskRepository.repository

        if hasProject || hasSection {
            let effectiveProject: UUID?
            if hasProject {
                effectiveProject =
                    patch["project_id"] == .null
                    ? nil
                    : try TasksStructuredCreateArguments.optionalProjectID(patch["project_id"])
            } else {
                effectiveProject = task.projectID
            }

            let effectiveSection: UUID?
            if hasSection {
                effectiveSection =
                    patch["section_id"] == .null
                    ? nil
                    : try TasksStructuredCreateArguments.optionalUUID(patch["section_id"], field: "section_id")
            } else if hasProject {
                effectiveSection = effectiveProject == task.projectID ? task.sectionID : nil
            } else {
                effectiveSection = task.sectionID
            }

            try TasksMutationToolSupport.validateProjectSectionAssignment(
                projectID: effectiveProject,
                sectionID: effectiveSection,
                repo: repo
            )
            return (effectiveProject, effectiveSection)
        }

        guard let parentID, let proposedParentID = parentID else { return nil }
        let parent = try TasksMutationToolSupport.liveTask(id: proposedParentID, context: context)
        try TasksMutationToolSupport.validateProjectSectionAssignment(
            projectID: parent.projectID,
            sectionID: parent.sectionID,
            repo: repo
        )
        return (parent.projectID, parent.sectionID)
    }
}

private struct TasksUpdatePatch {
    let title: String??
    let notes: String??
    let dueDate: Date??
    let deadlineAt: Date??
    let priority: TaskPriority?
    let tags: [String]??
    let parentID: UUID??
    let recurrenceRule: String??
    let reminders: [ReminderRule]??

    static func parse(_ patch: [String: JSONValue]) throws -> Self {
        _ = try TasksStructuredCreateArguments.optionalString(patch["due_string"], field: "due_string")
        // project_id and section_id are resolved in call() after the update closure. Validate non-null
        // UUIDs early here so we fail fast with a clear error before touching anything.
        if patch["project_id"] != .null {
            _ = try TasksStructuredCreateArguments.optionalProjectID(patch["project_id"])
        }
        if patch["section_id"] != .null {
            _ = try TasksStructuredCreateArguments.optionalUUID(patch["section_id"], field: "section_id")
        }

        return Self(
            title: try nullableTitle(patch["title"]),
            notes: try nullableString(patch["notes"], field: "notes"),
            dueDate: try nullableDueDate(patch["due_date"]),
            deadlineAt: try nullableDeadlineAt(patch["deadline_date"]),
            priority: try optionalPriority(patch["priority"]),
            tags: try nullableTags(patch["tags"]),
            parentID: try nullableUUID(patch["parent_id"], field: "parent_id"),
            recurrenceRule: try nullableRecurrenceRule(patch["recurrence_rule"]),
            reminders: try nullableReminders(patch["reminders"])
        )
    }

    @MainActor
    func apply(to task: TaskItem) {
        if let title {
            task.title = title ?? task.title
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
        if let parentID {
            task.parentTaskID = parentID
        }
        if let recurrenceRule {
            task.recurrenceRule = recurrenceRule
        }
        if let reminders {
            task.reminders = reminders ?? []
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

    private static func nullableUUID(_ value: JSONValue?, field: String) throws -> UUID?? {
        guard let value else { return nil }
        if value == .null {
            return .some(nil)
        }
        guard let text = value.stringValue, let id = UUID(uuidString: text) else {
            throw AgentError.validation("\(field) must be a valid UUID")
        }
        return .some(id)
    }

    private static func nullableRecurrenceRule(_ value: JSONValue?) throws -> String?? {
        guard let value else { return nil }
        if value == .null {
            return .some(nil)
        }
        return .some(try TasksStructuredCreateArguments.optionalRecurrenceRule(value))
    }

    private static func nullableReminders(_ value: JSONValue?) throws -> [ReminderRule]?? {
        guard let value else { return nil }
        if value == .null {
            return .some(nil)
        }
        return .some(try TasksStructuredCreateArguments.optionalReminders(value))
    }
}
