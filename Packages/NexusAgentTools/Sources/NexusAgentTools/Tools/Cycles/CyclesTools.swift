import Foundation
import NexusCore

// MARK: - cycles.list

public struct CyclesListTool: AgentTool {
    public let name = "cycles.list"
    public let description = """
        Lists non-deleted cycles (time-boxed sprints) ascending by start date, \
        optionally filtered by status (upcoming, active, completed).
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "status": .string(
                enumValues: CycleStatus.allCases.map(\.rawValue),
                description: "Optional CycleStatus filter."
            )
        ],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        var cycles = try context.cycleRepository.allActive()
        if let statusValue = args["status"] {
            guard let text = statusValue.stringValue, let status = CycleStatus(rawValue: text) else {
                throw AgentError.validation(
                    "Invalid status. Expected one of: "
                        + CycleStatus.allCases.map(\.rawValue).joined(separator: ", ")
                )
            }
            cycles = cycles.filter { $0.status == status }
        }
        return try TasksToolJSON.encode(CycleListResponseDTO(cycles: cycles.map(CycleDTO.init(from:))))
    }
}

// MARK: - cycles.assign_task

public struct CyclesAssignTool: AgentTool {
    public let name = "cycles.assign_task"
    public let description = """
        Assigns a task to a cycle (or clears the assignment with null). Routes \
        through the repository so the cycleChanged activity event is recorded. \
        Returns the updated task DTO.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID."),
            "cycle_id": .anyOf(
                [.string(description: "Cycle UUID."), .null(description: "Clear the cycle assignment.")],
                description: "Cycle UUID, or null to clear."
            ),
        ],
        required: ["task_id", "cycle_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let taskID = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let cycleID: UUID?
        if args["cycle_id"] == .null {
            cycleID = nil
        } else {
            cycleID = try TasksToolArguments.requiredUUID(args["cycle_id"], field: "cycle_id")
        }
        let task = try TasksMutationToolSupport.liveTask(id: taskID, context: context)
        do {
            try context.taskRepository.repository.assignCycle(task, to: cycleID)
        } catch let error as TaskItemRepositoryError {
            throw AgentError.validation("cycle assignment failed: \(error)")
        }
        return try TasksToolJSON.encode(TaskDTO(from: task))
    }
}
