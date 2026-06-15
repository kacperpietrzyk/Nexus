import Foundation
import NexusCore

public struct TasksInstantiateTemplateTool: AgentTool {
    public let name = "tasks.instantiate_template"
    public let description =
        "Creates a new live task (including subtasks, links, relative reminders, and note content) from a task template. Dates start empty."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "template_id": .string(description: "Template task UUID (isTemplate == true).")
        ],
        required: ["template_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["template_id"], field: "template_id")
        let template = try TasksMutationToolSupport.liveTask(id: id, context: context)
        guard template.isTemplate else {
            throw AgentError.validation("Task \(id.uuidString) is not a template")
        }
        let instance = try TemplateInstantiator(tasks: context.taskRepository.repository)
            .instantiate(template)
        for row in try TasksMutationToolSupport.allTasks(in: context) where row.deletedAt == nil {
            await TasksToolSearchIndexing.reflect(row, in: context.searchIndex)
        }
        return try TasksToolJSON.encode(TaskNotesContentStore.dto(for: instance, context: context))
    }
}
