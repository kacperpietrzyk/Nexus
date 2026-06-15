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

// MARK: - Support

/// Shared helpers for the cycle write tools. `requiredISODate` is reused by
/// later tranche tasks (e.g. `tasks.set_reminders`, stats) — keep the name
/// `requiredISODate(_:field:)` stable. `internal` is sufficient: every reuser
/// lives in this same `NexusAgentTools` target. A future tool in the separate
/// `NexusAgentToolsExtras` target would need this enum + member promoted to
/// `public` rather than duplicating it.
enum CyclesToolSupport {
    static func requiredISODate(_ value: JSONValue?, field: String) throws -> Date {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required date field: \(field)")
        }
        // Delegate to the shared ISO8601 fallback cascade (fractional then plain)
        // so the parse logic lives in exactly one place — same primitive
        // `CalendarEventArguments.requiredDate` uses. We keep our own
        // field-named error so callers see which field was malformed.
        guard let date = ScheduleDTOFormatter.date(text) else {
            throw AgentError.validation("\(field) must be an ISO8601 date, got '\(text)'")
        }
        return date
    }

    @MainActor
    static func liveCycle(id: UUID, context: AgentContext) throws -> Cycle {
        guard let cycle = try context.cycleRepository.find(id: id) else {
            throw AgentError.notFound("Cycle not found: \(id.uuidString)")
        }
        return cycle
    }
}

// MARK: - cycles.create

public struct CyclesCreateTool: AgentTool {
    public let name = "cycles.create"
    public let description = "Creates a cycle (sprint) with a name and start/end dates."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "name": .string(description: "Cycle name."),
            "start_at": .string(description: "ISO8601 start date."),
            "end_at": .string(description: "ISO8601 end date."),
        ],
        required: ["name", "start_at", "end_at"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        let startAt = try CyclesToolSupport.requiredISODate(args["start_at"], field: "start_at")
        let endAt = try CyclesToolSupport.requiredISODate(args["end_at"], field: "end_at")
        guard endAt > startAt else { throw AgentError.validation("end_at must be after start_at") }
        let cycle = try context.cycleRepository.create(name: name, startAt: startAt, endAt: endAt)
        return try TasksToolJSON.encode(CycleDTO(from: cycle))
    }
}

// MARK: - cycles.update

public struct CyclesUpdateTool: AgentTool {
    public let name = "cycles.update"
    public let description = "Updates a cycle's name and start/end dates."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "cycle_id": .string(description: "Cycle UUID."),
            "name": .string(description: "Cycle name."),
            "start_at": .string(description: "ISO8601 start date."),
            "end_at": .string(description: "ISO8601 end date."),
        ],
        required: ["cycle_id", "name", "start_at", "end_at"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["cycle_id"], field: "cycle_id")
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        let startAt = try CyclesToolSupport.requiredISODate(args["start_at"], field: "start_at")
        let endAt = try CyclesToolSupport.requiredISODate(args["end_at"], field: "end_at")
        guard endAt > startAt else { throw AgentError.validation("end_at must be after start_at") }
        let cycle = try CyclesToolSupport.liveCycle(id: id, context: context)
        try context.cycleRepository.update(cycle, name: name, startAt: startAt, endAt: endAt)
        return try TasksToolJSON.encode(CycleDTO(from: cycle))
    }
}

// MARK: - cycles.set_status

public struct CyclesSetStatusTool: AgentTool {
    public let name = "cycles.set_status"
    public let description = "Sets a cycle's status: upcoming, active, or completed."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "cycle_id": .string(description: "Cycle UUID."),
            "status": .string(
                enumValues: CycleStatus.allCases.map(\.rawValue),
                description: "New status."
            ),
        ],
        required: ["cycle_id", "status"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["cycle_id"], field: "cycle_id")
        let statusText = try TasksToolArguments.requiredString(args["status"], field: "status")
        guard let status = CycleStatus(rawValue: statusText) else {
            throw AgentError.validation(
                "Invalid status '\(statusText)'. Expected one of: "
                    + CycleStatus.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        let cycle = try CyclesToolSupport.liveCycle(id: id, context: context)
        try context.cycleRepository.setStatus(status, on: cycle)
        return try TasksToolJSON.encode(CycleDTO(from: cycle))
    }
}

// MARK: - cycles.delete

public struct CyclesDeleteTool: AgentTool {
    public let name = "cycles.delete"
    public let description = "Soft-deletes a cycle by UUID."
    public let inputSchema: JSONSchema = .object(
        properties: ["cycle_id": .string(description: "Cycle UUID.")],
        required: ["cycle_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["cycle_id"], field: "cycle_id")
        let cycle = try CyclesToolSupport.liveCycle(id: id, context: context)
        try context.cycleRepository.softDelete(cycle)
        return .object(["id": .string(cycle.id.uuidString), "deleted": .bool(true)])
    }
}
