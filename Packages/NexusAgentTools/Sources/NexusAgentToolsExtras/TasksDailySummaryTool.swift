import Foundation
import NexusAgentTools
import NexusCore

public struct TasksDailySummaryTool: AgentTool {
    public let name = "tasks.daily_summary"
    public let description = """
        Returns the Today screen summary for agent clients: hero brief, today tasks,
        upcoming tasks, and AM/PM/evening focus buckets.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "date": .string(description: "Optional local date in YYYY-MM-DD format. Defaults to today.")
        ],
        required: []
    )

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let referenceDate = try date(from: args["date"], fallback: context.now())
        guard let heroBriefService = context.heroBriefService else {
            throw AgentError.internalError("tasks.daily_summary requires a hero brief service")
        }

        let modelContext = context.modelContext.context
        let todayQuery = TodayQuery(calendar: calendar)
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let overdue = try todayQuery.overdue(now: referenceDate, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let dueToday = try todayQuery.today(now: referenceDate, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let upcoming = try UpcomingQuery(calendar: calendar)
            .next(days: 7, from: referenceDate, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let todayTasks = overdue + dueToday
        let heroBriefValue = await heroBriefService.brief(context: modelContext, now: referenceDate)
        let heroBrief = heroBriefString(from: heroBriefValue)

        let summary = DailySummaryDTO(
            heroBrief: heroBrief,
            today: todayTasks.map(TaskDTO.init(from:)),
            upcoming: upcoming.map(TaskDTO.init(from:)),
            focusBuckets: focusBuckets(from: todayTasks)
        )
        return try encode(summary)
    }

    private func date(from value: JSONValue?, fallback: Date) throws -> Date {
        guard let value else { return fallback }
        guard let text = value.stringValue else {
            throw AgentError.validation("date must be YYYY-MM-DD")
        }
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw AgentError.validation("date must be YYYY-MM-DD")
        }

        var components = DateComponents()
        components.calendar = calendar
        let parts = text.split(separator: "-").compactMap { Int(String($0)) }
        guard parts.count == 3 else {
            throw AgentError.validation("date must be YYYY-MM-DD")
        }
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]

        guard
            let date = calendar.date(from: components),
            calendar.component(.year, from: date) == parts[0],
            calendar.component(.month, from: date) == parts[1],
            calendar.component(.day, from: date) == parts[2]
        else {
            throw AgentError.validation("date must be YYYY-MM-DD")
        }
        return date
    }

    @MainActor
    private func heroBriefString(from value: Any) -> String {
        if let text = value as? String {
            return text
        }
        return String(describing: value)
    }

    @MainActor
    private func focusBuckets(from tasks: [TaskItem]) -> FocusBucketsDTO {
        var am: [TaskDTO] = []
        var pm: [TaskDTO] = []
        var evening: [TaskDTO] = []

        for task in tasks {
            let dto = TaskDTO(from: task)
            guard let dueAt = task.dueAt else {
                am.append(dto)
                continue
            }
            let hour = calendar.component(.hour, from: dueAt)
            switch hour {
            case 0..<12:
                am.append(dto)
            case 12..<18:
                pm.append(dto)
            default:
                evening.append(dto)
            }
        }

        return FocusBucketsDTO(am: am, pm: pm, evening: evening)
    }

    private func encode(_ value: some Encodable) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
