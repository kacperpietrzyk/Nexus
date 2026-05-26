import Foundation
import NexusCore
import SwiftData

public struct TasksListTool: AgentTool {
    public let name = "tasks.list"
    public let description =
        "Lists tasks with bucket, state, tag, sort, and pagination filters. state=any includes deleted rows."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "filter": .object(
                properties: [
                    "bucket": .string(
                        enumValues: ["today", "upcoming", "inbox", "all"],
                        description: "Task bucket to list. Defaults to all."
                    ),
                    "state": .string(
                        enumValues: ["open", "done", "any"],
                        description: "Task lifecycle state. Defaults to open. any includes deleted rows."
                    ),
                    "tag": .string(description: "Tag to match."),
                    "project_id": .string(description: "Reserved project identifier filter."),
                ],
                required: [],
                description: "Optional task filters."
            ),
            "sort": .string(
                enumValues: ["due", "priority", "created"],
                description: "Sort mode. Defaults to due."
            ),
            "limit": .integer(minimum: 1, maximum: 1_000, description: "Maximum tasks to return."),
            "offset": .integer(minimum: 0, maximum: nil, description: "Number of matching tasks to skip."),
        ],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let filter = try filterObject(from: args["filter"])
        let bucketValue = try stringValue(filter["bucket"], field: "filter.bucket") ?? Bucket.all.rawValue
        let bucket = try Bucket(rawValue: bucketValue)
            .unwrapValidation("Invalid bucket filter")
        let stateValue = try stringValue(filter["state"], field: "filter.state") ?? State.open.rawValue
        let state = try State(rawValue: stateValue)
            .unwrapValidation("Invalid state filter")
        let sortValue = try stringValue(args["sort"], field: "sort") ?? Sort.due.rawValue
        let sort = try Sort(rawValue: sortValue)
            .unwrapValidation("Invalid sort")
        let tag = try trimmedOptionalString(filter["tag"], field: "filter.tag")
        let projectID = try trimmedOptionalString(filter["project_id"], field: "filter.project_id")
        if projectID != nil {
            throw AgentError.validation("project_id filter is reserved until Projects land")
        }
        let limit = try TasksToolArguments.boundedInt(
            args["limit"],
            field: "limit",
            default: 100,
            range: 1...1_000
        )
        let offset = try TasksToolArguments.minimumInt(
            args["offset"],
            field: "offset",
            default: 0,
            minimum: 0
        )

        let descriptor = FetchDescriptor<TaskItem>()
        let now = context.now()
        let calendar = Calendar.current
        let startOfTomorrow = calendar.dateInterval(of: .day, for: now)?.end ?? now

        var tasks = try context.modelContext.context.fetch(descriptor)
        tasks = tasks.filter { task in
            matches(task, state: state)
                && matches(task, bucket: bucket, startOfTomorrow: startOfTomorrow)
                && matches(task, tag: tag)
        }
        tasks.sort { lhs, rhs in
            compare(lhs, rhs, sort: sort)
        }

        let total = tasks.count
        let pagedTasks = Array(tasks.dropFirst(min(offset, total)).prefix(limit))
        let response = TaskListResponseDTO(
            tasks: pagedTasks.map(TaskDTO.init(from:)),
            total: total,
            hasMore: offset + pagedTasks.count < total
        )
        return try TasksToolJSON.encode(response)
    }

    private enum Bucket: String {
        case today
        case upcoming
        case inbox
        case all
    }

    private enum State: String {
        case open
        case done
        case any
    }

    private enum Sort: String {
        case due
        case priority
        case created
    }

    private func matches(_ task: TaskItem, state: State) -> Bool {
        switch state {
        case .open:
            task.deletedAt == nil && task.status == .open
        case .done:
            task.deletedAt == nil && task.status == .done
        case .any:
            true
        }
    }

    private func matches(_ task: TaskItem, bucket: Bucket, startOfTomorrow: Date) -> Bool {
        switch bucket {
        case .today:
            guard let dueAt = task.dueAt else { return false }
            return dueAt < startOfTomorrow
        case .upcoming:
            guard let dueAt = task.dueAt else { return false }
            return dueAt >= startOfTomorrow
        case .inbox:
            return task.dueAt == nil
        case .all:
            return true
        }
    }

    private func matches(_ task: TaskItem, tag: String?) -> Bool {
        guard let tag, !tag.isEmpty else { return true }
        let normalized = tag.lowercased()
        return task.tags.contains { $0.lowercased() == normalized }
    }

    private func compare(_ lhs: TaskItem, _ rhs: TaskItem, sort: Sort) -> Bool {
        switch sort {
        case .due:
            if lhs.dueAt != rhs.dueAt {
                switch (lhs.dueAt, rhs.dueAt) {
                case (.some(let left), .some(let right)):
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
            }
            return tieBreak(lhs, rhs)
        case .priority:
            if lhs.priorityRaw != rhs.priorityRaw {
                return lhs.priorityRaw > rhs.priorityRaw
            }
            return tieBreak(lhs, rhs)
        case .created:
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return tieBreak(lhs, rhs)
        }
    }

    private func tieBreak(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.priorityRaw != rhs.priorityRaw {
            return lhs.priorityRaw > rhs.priorityRaw
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func filterObject(from value: JSONValue?) throws -> [String: JSONValue] {
        guard let value else { return [:] }
        guard let object = value.objectValue else {
            throw AgentError.validation("filter must be an object")
        }
        return object
    }

    private func stringValue(_ value: JSONValue?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be a string")
        }
        return text
    }

    private func trimmedOptionalString(_ value: JSONValue?, field: String) throws -> String? {
        guard let text = try stringValue(value, field: field) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.validation("\(field) cannot be empty")
        }
        return trimmed
    }
}

extension Optional {
    fileprivate func unwrapValidation(_ message: String) throws -> Wrapped {
        guard let value = self else {
            throw AgentError.validation(message)
        }
        return value
    }
}
