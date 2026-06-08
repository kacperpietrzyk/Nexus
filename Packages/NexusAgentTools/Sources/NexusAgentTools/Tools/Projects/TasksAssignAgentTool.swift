import Foundation
import NexusCore

/// Sets (or clears) a task's `assignedAgent` (Projects tier, spec §4.5 / §8).
///
/// Pure metadata (invariant I8): assignment NEVER affects scheduling, visibility,
/// or `status` — so it routes through `TaskItemRepository.update`, which saves
/// without touching status. `agent: null` clears the assignment back to self.
public struct TasksAssignAgentTool: AgentTool {
    public let name = "tasks.assign_agent"
    public let description = """
        Assigns a task to an agent (codex or claude), or pass agent: null to clear it \
        back to self. Pure metadata — never changes the task's status, scheduling, or \
        visibility.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID."),
            "agent": .anyValue(description: "AgentAssignee raw value (codex | claude), or null for self."),
        ],
        required: ["task_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let task = try TasksMutationToolSupport.liveTask(id: id, context: context)

        let agentValue = args["agent"]
        let newAgentRaw: String?
        if agentValue == nil || agentValue == .null {
            newAgentRaw = nil
        } else {
            guard let text = agentValue?.stringValue else {
                throw AgentError.validation("agent must be a string or null")
            }
            guard let agent = AgentAssignee(rawValue: text) else {
                throw AgentError.validation(
                    "Invalid agent '\(text)'. Expected one of: "
                        + AgentAssignee.allCases.map(\.rawValue).joined(separator: ", ")
                )
            }
            newAgentRaw = agent.rawValue
        }

        try context.taskRepository.repository.update(task) { task in
            task.assignedAgent = newAgentRaw
        }

        await TasksToolSearchIndexing.reflect(task, in: context.searchIndex)
        return try TasksToolJSON.encode(TaskNotesContentStore.dto(for: task, context: context))
    }
}

// MARK: - agents.queue

/// The MCP-exposed work queue for an agent (spec §8 / §10): tasks with
/// `assignedAgent == agent`, `workflowState ∈ {todo, inProgress}`, not soft-deleted.
/// This is how an external agent (Codex/Claude) pulls its assigned work.
public struct AgentsQueueTool: AgentTool {
    public let name = "agents.queue"
    public let description = """
        Returns the work queue for an agent: tasks assigned to that agent whose \
        workflow state is todo or inProgress (and not closed). The agent pulls its \
        work from here and reports progress back via tasks.set_workflow_state.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "agent": .string(
                enumValues: AgentAssignee.allCases.map(\.rawValue),
                description: "AgentAssignee raw value (codex | claude)."
            )
        ],
        required: ["agent"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let agentText = try TasksToolArguments.requiredString(args["agent"], field: "agent")
        guard let agent = AgentAssignee(rawValue: agentText) else {
            throw AgentError.validation(
                "Invalid agent '\(agentText)'. Expected one of: "
                    + AgentAssignee.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        let tasks = try context.labelRepository.agentQueue(for: agent)
        return try TasksToolJSON.encode(tasks.map { try TaskNotesContentStore.dto(for: $0, context: context) })
    }
}
