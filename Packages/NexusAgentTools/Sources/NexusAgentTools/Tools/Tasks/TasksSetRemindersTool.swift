import Foundation
import NexusCore

/// Sets (or clears, with an empty array) the reminder rules on a task. This tool
/// only writes the `[ReminderRule]` data; rescheduling system notifications is the
/// app's observe-path responsibility (no scheduler is injected into MCP tools).
public struct TasksSetRemindersTool: AgentTool {
    public let name = "tasks.set_reminders"
    public let description = """
        Replaces a task's reminders. Each rule is either \
        {"kind":"absolute","at":ISO8601,"repeat":"daily"|"weekly"|null} or \
        {"kind":"relative","offset":SECONDS,"anchor":"due"|"deadline"}. \
        An empty array clears all reminders.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID."),
            "reminders": .array(
                items: .object(
                    properties: [
                        "kind": .string(enumValues: ["absolute", "relative"], description: "Rule kind."),
                        "at": .string(description: "ISO8601 fire date (absolute)."),
                        "repeat": .string(
                            enumValues: ["daily", "weekly"],
                            description: "Repeat (absolute, optional)."
                        ),
                        "offset": .number(description: "Seconds relative to anchor; negative = before (relative)."),
                        "anchor": .string(enumValues: ["due", "deadline"], description: "Relative anchor."),
                    ],
                    required: ["kind"]
                ),
                description: "Reminder rules. Empty = clear."
            ),
        ],
        required: ["task_id", "reminders"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let task = try TasksMutationToolSupport.liveTask(id: id, context: context)
        guard let rawRules = args["reminders"]?.arrayValue else {
            throw AgentError.validation("reminders must be an array")
        }
        let rules = try rawRules.map { try Self.parseRule($0) }
        try context.taskRepository.repository.update(task) { task in
            task.reminders = rules
        }
        await TasksToolSearchIndexing.reflect(task, in: context.searchIndex)
        return .object([
            "id": .string(id.uuidString),
            "reminder_count": .int(rules.count),
        ])
    }

    static func parseRule(_ value: JSONValue) throws -> ReminderRule {
        switch value["kind"]?.stringValue {
        case "absolute":
            guard let atText = value["at"]?.stringValue else {
                throw AgentError.validation("absolute reminder requires 'at'")
            }
            let at = try CyclesToolSupport.requiredISODate(.string(atText), field: "at")
            let repeats = try Self.parseRepeat(value["repeat"])
            return .absolute(at: at, repeats: repeats)
        case "relative":
            guard let offset = value["offset"]?.doubleValue else {
                throw AgentError.validation("relative reminder requires numeric 'offset'")
            }
            guard let anchor = value["anchor"]?.stringValue.flatMap(ReminderAnchor.init(rawValue:)) else {
                throw AgentError.validation("relative reminder requires anchor 'due' or 'deadline'")
            }
            return .relative(offset: offset, anchor: anchor)
        default:
            throw AgentError.validation("reminder 'kind' must be 'absolute' or 'relative'")
        }
    }

    /// Parses the optional `repeat` field. Absent/null → nil (one-shot); a present
    /// but unrecognized value throws rather than silently degrading to one-shot,
    /// matching the strictness of the relative branch's `anchor` validation.
    private static func parseRepeat(_ value: JSONValue?) throws -> ReminderRepeat? {
        guard let value, value != .null else { return nil }
        guard let raw = value.stringValue, let repeats = ReminderRepeat(rawValue: raw) else {
            throw AgentError.validation("absolute reminder 'repeat' must be 'daily' or 'weekly'")
        }
        return repeats
    }
}
