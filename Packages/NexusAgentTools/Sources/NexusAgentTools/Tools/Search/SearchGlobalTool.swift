import Foundation
import NexusCore

/// Unified cross-entity search over the in-memory `SearchIndex`.
///
/// `kinds` omitted (or empty) searches every indexed kind; supplying raw `ItemKind`
/// values restricts the result set. Hits come back ranked (score desc, then recency).
public struct SearchGlobalTool: AgentTool {
    public let name = "search.global"
    public let description = """
        Searches all entities (tasks, notes, projects, people, …) by text. Optionally \
        restrict to specific kinds. Returns ranked hits.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "query": .string(description: "Search text."),
            "kinds": .array(
                items: .string(description: "ItemKind raw value, e.g. task, note, project, person."),
                description: "Optional kind filter. Omit to search all."
            ),
            "limit": .integer(minimum: 1, maximum: 100, description: "Max results (default 20)."),
        ],
        required: ["query"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let query = try TasksToolArguments.requiredString(args["query"], field: "query")
        let limit = try TasksToolArguments.boundedInt(
            args["limit"],
            field: "limit",
            default: 20,
            range: 1...100
        )

        var kinds: Set<ItemKind>?
        if let raw = args["kinds"]?.arrayValue {
            let parsed = raw.compactMap { $0.stringValue.flatMap(ItemKind.init(rawValue:)) }
            kinds = parsed.isEmpty ? nil : Set(parsed)
        }

        let hits = await context.searchIndex.search(query, kinds: kinds, limit: limit)
        return .object(["results": try TasksToolJSON.encode(hits.map(SearchHitDTO.init(from:)))])
    }
}
