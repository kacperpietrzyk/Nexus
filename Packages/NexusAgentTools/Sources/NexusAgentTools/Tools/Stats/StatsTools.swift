import Foundation
import NexusCore

// MARK: - stats.goals.get

/// `stats.goals.get`: returns the user's daily/weekly task-completion targets.
/// Thin wrapper over `UserDefaultsGoalsPreferencesStore` (the
/// `CalendarPreferences*` pattern). Read-only.
public struct StatsGoalsGetTool: AgentTool {
    public let name = "stats.goals.get"
    public let description = "Returns the user's daily/weekly task-completion targets."
    public let inputSchema: JSONSchema = .object(properties: [:], required: [])

    private let store: UserDefaultsGoalsPreferencesStore

    public init(store: UserDefaultsGoalsPreferencesStore = .init()) {
        self.store = store
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        try TasksToolJSON.encode(GoalsDTO(from: store.load()))
    }
}

// MARK: - stats.goals.update

/// `stats.goals.update`: partial update of the completion targets. Only fields
/// present in `args` change; everything else is preserved. Returns the updated
/// goals as a `GoalsDTO`.
public struct StatsGoalsUpdateTool: AgentTool {
    public let name = "stats.goals.update"
    public let description = "Updates daily and/or weekly completion targets. Only provided fields change."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "daily_completion_target": .integer(minimum: 0, description: "Tasks/day target (0 = off)."),
            "weekly_completion_target": .integer(minimum: 0, description: "Tasks/week target (0 = off)."),
        ],
        required: []
    )

    private let store: UserDefaultsGoalsPreferencesStore

    public init(store: UserDefaultsGoalsPreferencesStore = .init()) {
        self.store = store
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        var goals = store.load()
        if let daily = args["daily_completion_target"]?.intValue { goals.dailyCompletionTarget = daily }
        if let weekly = args["weekly_completion_target"]?.intValue { goals.weeklyCompletionTarget = weekly }
        store.save(goals)
        return try TasksToolJSON.encode(GoalsDTO(from: goals))
    }
}

// MARK: - stats.productivity

/// `stats.productivity`: counts tasks completed (by `lastCompletedAt`) within an
/// inclusive ISO8601 date range. Read-only.
public struct StatsProductivityTool: AgentTool {
    public let name = "stats.productivity"
    public let description = "Counts tasks completed within an ISO8601 date range."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "from": .string(description: "ISO8601 range start (inclusive)."),
            "to": .string(description: "ISO8601 range end (inclusive)."),
        ],
        required: ["from", "to"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let from = try CyclesToolSupport.requiredISODate(args["from"], field: "from")
        let to = try CyclesToolSupport.requiredISODate(args["to"], field: "to")
        guard to >= from else {
            throw AgentError.validation("'to' must be on or after 'from'")
        }
        let tasks = try context.taskRepository.repository.completedTasks(
            in: DateInterval(start: from, end: to)
        )
        let dto = ProductivityDTO(
            from: ScheduleDTOFormatter.string(from),
            to: ScheduleDTOFormatter.string(to),
            completedCount: tasks.count
        )
        return try TasksToolJSON.encode(dto)
    }
}
