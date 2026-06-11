import Foundation
import NexusCore

// MARK: - activity.get

/// Read-only audit-log access (Tranche 2 Plan B, spec §6.3). The agent can
/// READ the log but NEVER write it — entries are written only by repository
/// mutation points the agent already drives through the task tools (I-B1).
/// Deliberately no live-task existence gate: a soft-deleted task's history
/// (including its `deleted` event) must stay readable; unknown ids just
/// return an empty list.
public struct ActivityGetTool: AgentTool {
    public let name = "activity.get"
    public let description =
        "Reads the append-only activity log for a task (created/completed/reopened/workflow/project/"
        + "priority/due/cycle changes, deletion), newest first. Read-only."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "item_id": .string(description: "Subject task UUID."),
            "item_kind": .string(enumValues: ["task"], description: "Only 'task' is recorded in v1."),
            "limit": .integer(minimum: 1, maximum: 200, description: "Max events to return (default 50)."),
        ],
        required: ["item_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        guard let idText = args["item_id"]?.stringValue, let id = UUID(uuidString: idText) else {
            throw AgentError.validation("item_id must be a valid UUID")
        }
        if let kindText = args["item_kind"]?.stringValue, kindText != ItemKind.task.rawValue {
            throw AgentError.validation("item_kind must be 'task'")
        }
        let limit = AgentToolArgs.limit(args, default: 50, max: 200)
        let entries = try context.activityEntryRepository.entries(for: id, kind: .task, limit: limit)
        return try TasksToolJSON.encode(entries.map { ActivityEntryDTO(from: $0) })
    }
}
