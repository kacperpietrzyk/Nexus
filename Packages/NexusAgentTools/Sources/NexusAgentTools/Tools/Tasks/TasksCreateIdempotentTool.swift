import Foundation
import NexusCore
import SwiftData

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
            "project_id": .string(description: "Optional opaque project UUID; accepted but not persisted yet."),
        ],
        required: ["external_source_id", "title"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        try TasksStructuredCreateArguments.rejectReservedFields(args)
        let externalSourceID = try TasksStructuredCreateArguments.trimmedRequiredString(
            args["external_source_id"],
            field: "external_source_id"
        )
        let metadata = try metadata(from: args["external_source_metadata"])
        let fields = try TasksStructuredCreateArguments.parse(args)

        if let existing = try existingTask(externalSourceID: externalSourceID, context: context) {
            if let oldMetadata = existing.externalSourceMetadata, let metadata {
                if oldMetadata != metadata {
                    throw AgentError.conflict("external_source_metadata mismatch for \(externalSourceID)")
                }
            }

            try context.taskRepository.repository.update(existing) { task in
                task.title = fields.title
                if args["notes"] != nil {
                    task.body = fields.notes ?? ""
                }
                if args["due_date"] != nil {
                    task.dueAt = fields.dueDate
                }
                if args["deadline_date"] != nil {
                    task.deadlineAt = fields.deadlineAt
                }
                if args["priority"] != nil {
                    task.priorityRaw = fields.priority.rawValue
                }
                if args["tags"] != nil {
                    task.tags = fields.tags
                }
                if task.externalSourceMetadata == nil {
                    task.externalSourceMetadata = metadata
                }
            }
            await TasksToolSearchIndexing.reflect(existing, in: context.searchIndex)
            let response = IdempotentResponseDTO(task: TaskDTO(from: existing), wasCreated: false)
            return try TasksToolJSON.encode(response)
        }

        let task = TaskItem(
            title: fields.title,
            body: fields.notes ?? "",
            dueAt: fields.dueDate,
            deadlineAt: fields.deadlineAt,
            priority: fields.priority,
            tags: fields.tags
        )
        task.externalSourceID = externalSourceID
        task.externalSourceMetadata = metadata
        try context.taskRepository.repository.insert(task)
        await context.searchIndex.upsert(IndexedDocument(task))

        let response = IdempotentResponseDTO(task: TaskDTO(from: task), wasCreated: true)
        return try TasksToolJSON.encode(response)
    }

    @MainActor
    private func existingTask(externalSourceID: String, context: AgentContext) throws -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.externalSourceID == externalSourceID
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
