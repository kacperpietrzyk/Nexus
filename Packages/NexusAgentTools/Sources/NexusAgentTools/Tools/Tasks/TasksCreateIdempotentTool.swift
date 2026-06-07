import Foundation
import NexusCore
import SwiftData

/// Bundles all write parameters for the idempotent upsert to avoid long parameter lists.
private struct IdempotentWriteParams {
    let args: JSONValue
    let fields: TasksStructuredCreateFields
    let externalSourceID: String
    let metadata: Data?
    let projectID: UUID?
    let sectionID: UUID?
    let parentID: UUID?
    let recurrence: String?
    let reminders: [ReminderRule]
}

public struct TasksCreateIdempotentTool: AgentTool {
    public let name = "tasks.create_idempotent"
    public let description =
        "Creates or updates one structured task by external_source_id without duplicating rows."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "external_source_id": .string(description: "Stable source identifier, e.g. todoist:8237162."),
            "external_source_metadata": .string(description: "Optional Base64-encoded source metadata."),
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
        required: ["external_source_id", "title"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let write = try IdempotentWriteParams(
            args: args,
            fields: TasksStructuredCreateArguments.parse(args),
            externalSourceID: TasksStructuredCreateArguments.trimmedRequiredString(
                args["external_source_id"],
                field: "external_source_id"
            ),
            metadata: metadata(from: args["external_source_metadata"]),
            projectID: TasksStructuredCreateArguments.optionalProjectID(args["project_id"]),
            sectionID: TasksStructuredCreateArguments.optionalUUID(
                args["section_id"], field: "section_id"
            ),
            parentID: TasksStructuredCreateArguments.optionalUUID(
                args["parent_id"], field: "parent_id"
            ),
            recurrence: TasksStructuredCreateArguments.optionalRecurrenceRule(args["recurrence_rule"]),
            reminders: TasksStructuredCreateArguments.optionalReminders(args["reminders"])
        )

        let repo = context.taskRepository.repository

        if let existing = try existingTask(externalSourceID: write.externalSourceID, context: context) {
            return try await updateExisting(existing, write: write, repo: repo, context: context)
        }

        let task = TaskItem(
            title: write.fields.title,
            body: write.fields.notes ?? "",
            dueAt: write.fields.dueDate,
            deadlineAt: write.fields.deadlineAt,
            priority: write.fields.priority,
            tags: write.fields.tags,
            recurrenceRule: write.recurrence,
            parentTaskID: write.parentID
        )
        task.reminders = write.reminders
        task.externalSourceID = write.externalSourceID
        task.externalSourceMetadata = write.metadata
        try repo.insert(task)
        try assignIfNeeded(task, projectID: write.projectID, sectionID: write.sectionID, repo: repo)
        await context.searchIndex.upsert(IndexedDocument(task))

        let response = IdempotentResponseDTO(task: TaskDTO(from: task), wasCreated: true)
        return try TasksToolJSON.encode(response)
    }

    @MainActor
    private func updateExisting(
        _ existing: TaskItem,
        write: IdempotentWriteParams,
        repo: TaskItemRepository,
        context: AgentContext
    ) async throws -> JSONValue {
        if let oldMetadata = existing.externalSourceMetadata, let incomingMetadata = write.metadata {
            if oldMetadata != incomingMetadata {
                throw AgentError.conflict(
                    "external_source_metadata mismatch for \(write.externalSourceID)"
                )
            }
        }

        let args = write.args
        let fields = write.fields
        let parentID = write.parentID
        let recurrence = write.recurrence
        let reminders = write.reminders
        let metadata = write.metadata
        try repo.update(existing) { task in
            task.title = fields.title
            if args["notes"] != nil { task.body = fields.notes ?? "" }
            if args["due_date"] != nil { task.dueAt = fields.dueDate }
            if args["deadline_date"] != nil { task.deadlineAt = fields.deadlineAt }
            if args["priority"] != nil { task.priorityRaw = fields.priority.rawValue }
            if args["tags"] != nil { task.tags = fields.tags }
            if args["parent_id"] != nil { task.parentTaskID = parentID }
            if args["recurrence_rule"] != nil { task.recurrenceRule = recurrence }
            if args["reminders"] != nil { task.reminders = reminders }
            if task.externalSourceMetadata == nil { task.externalSourceMetadata = metadata }
        }
        // `repo.assign` sets BOTH projectID and sectionID, so an omitted arg must fall back to
        // the task's existing value rather than clobbering it to nil (mirrors the omit-≠-clear
        // invariant the field updates above honor). Only re-assign when at least one of the two
        // args is actually present.
        let hasProject = args["project_id"] != nil
        let hasSection = args["section_id"] != nil
        if hasProject || hasSection {
            let effectiveProject = hasProject ? write.projectID : existing.projectID
            let effectiveSection = hasSection ? write.sectionID : existing.sectionID
            try assign(existing, projectID: effectiveProject, sectionID: effectiveSection, repo: repo)
        }
        await TasksToolSearchIndexing.reflect(existing, in: context.searchIndex)
        let response = IdempotentResponseDTO(task: TaskDTO(from: existing), wasCreated: false)
        return try TasksToolJSON.encode(response)
    }

    @MainActor
    private func assignIfNeeded(
        _ task: TaskItem, projectID: UUID?, sectionID: UUID?, repo: TaskItemRepository
    ) throws {
        guard projectID != nil || sectionID != nil else { return }
        try assign(task, projectID: projectID, sectionID: sectionID, repo: repo)
    }

    @MainActor
    private func assign(
        _ task: TaskItem, projectID: UUID?, sectionID: UUID?, repo: TaskItemRepository
    ) throws {
        do {
            try repo.assign(task, toProject: projectID, section: sectionID)
        } catch {
            throw AgentError.validation("project/section assignment failed: \(error)")
        }
    }

    @MainActor
    private func existingTask(externalSourceID: String, context: AgentContext) throws -> TaskItem? {
        // Only dedup against LIVE tasks: a soft-deleted tombstone keeps its externalSourceID, so
        // matching it would silently mutate a dead row (the task stays invisible) instead of
        // re-creating it. Excluding deletedAt != nil makes a re-import of a deleted task come back
        // as a fresh task rather than overriding the user's delete.
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.externalSourceID == externalSourceID && task.deletedAt == nil
            }
        )
        return try context.modelContext.context.fetch(descriptor).first
    }

    private func metadata(from value: JSONValue?) throws -> Data? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("external_source_metadata must be a Base64 string")
        }
        guard let data = Data(base64Encoded: text) else {
            throw AgentError.validation("external_source_metadata must be valid Base64")
        }
        return data
    }
}
