import Foundation
import NexusCore

/// Writes a task's optional tracker `WorkflowState` (Projects tier, spec §4.2 / §5).
///
/// CRITICAL (invariant I1): this MUST go through `TaskItemRepository.setWorkflowState`,
/// the single sanctioned write path that reconciles `status` per table 5.1. The raw
/// `workflowStateRaw` setter is never touched directly from here.
///
/// `setWorkflowState` takes a non-optional `WorkflowState` — there is no
/// reconciliation path back to `nil` (a GTD task). Writing raw-nil would bypass I1,
/// so `workflow_state: null` is rejected with a validation error.
public struct TasksSetWorkflowStateTool: AgentTool {
    public let name = "tasks.set_workflow_state"
    public let description = """
        Sets a task's tracker workflow state. One of: backlog, todo, inProgress, \
        inReview, done, canceled, duplicate. The task's status is reconciled \
        deterministically (done sets completion; canceled/duplicate close it without \
        counting as completed work). Cannot be cleared to null via this tool.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID."),
            "workflow_state": .string(
                enumValues: WorkflowState.allCases.map(\.rawValue),
                description: "New WorkflowState (non-null)."
            ),
        ],
        required: ["task_id", "workflow_state"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")

        // Reject an explicit null: there is no reconciliation path back to a GTD task,
        // and writing raw-nil would bypass invariant I1.
        if args["workflow_state"] == .null {
            throw AgentError.validation("workflow_state cannot be null (no path back to a GTD task)")
        }
        let stateText = try TasksToolArguments.requiredString(args["workflow_state"], field: "workflow_state")
        guard let state = WorkflowState(rawValue: stateText) else {
            throw AgentError.validation(
                "Invalid workflow_state '\(stateText)'. Expected one of: "
                    + WorkflowState.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }

        let task = try TasksMutationToolSupport.liveTask(id: id, context: context)
        try context.taskRepository.repository.setWorkflowState(state, on: task)

        await TasksToolSearchIndexing.reflect(task, in: context.searchIndex)
        return try TasksToolJSON.encode(TaskDTO(from: task))
    }
}
