import Foundation
import NexusAgentTools
import NexusCore
import TasksFeature

public struct TasksCreateFromTextTool: AgentTool {
    public let name = "tasks.create_from_text"
    public let description = """
        Create a task from natural-language input using the TasksFeature parser pipeline.
        Supports PL/EN task phrases such as "buy milk tomorrow at 5pm" and
        "kup mleko jutro o 17".
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "text": .string(description: "Natural-language task input."),
            "locale": .string(
                enumValues: ["pl", "en", "auto"],
                description: "Parsing locale. Defaults to auto."
            ),
        ],
        required: ["text"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let text = try text(from: args["text"])
        let locale = try locale(from: args["locale"])
        guard let parser = context.nlParser else {
            throw AgentError.internalError("tasks.create_from_text requires an NL parser")
        }

        let raw = await parser.parse(text, locale: locale, now: context.now())
        guard let parsed = raw as? ParseResult else {
            throw AgentError.internalError("NL parser returned unexpected result")
        }

        let task = TaskItem(
            title: parsed.title,
            dueAt: parsed.dueAt,
            startAt: parsed.startAt,
            deadlineAt: parsed.deadlineAt,
            priority: parsed.priority ?? .none,
            tags: parsed.tags,
            recurrenceRule: parsed.recurrence
        )
        try context.taskRepository.repository.insert(task)
        await context.searchIndex.upsert(IndexedDocument(task))

        let data = try JSONEncoder().encode(TaskDTO(from: task))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func text(from value: JSONValue?) throws -> String {
        guard let raw = value?.stringValue else {
            throw AgentError.validation("Missing required string field: text")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.validation("text cannot be empty")
        }
        return trimmed
    }

    private func locale(from value: JSONValue?) throws -> Locale {
        guard let value else {
            return Locale.autoupdatingCurrent
        }
        guard let raw = value.stringValue else {
            throw AgentError.validation("locale must be one of: pl, en, auto")
        }
        switch raw {
        case "pl":
            return Locale(identifier: "pl_PL")
        case "en":
            return Locale(identifier: "en_US")
        case "auto":
            return Locale.autoupdatingCurrent
        default:
            throw AgentError.validation("locale must be one of: pl, en, auto")
        }
    }
}
