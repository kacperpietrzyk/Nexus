import Foundation
import NexusCore

/// Unified cross-entity search over the in-memory `SearchIndex`.
///
/// `kinds` omitted (or empty) searches every indexed kind; supplying raw `ItemKind`
/// values restricts the result set. A non-empty `kinds` array of only unrecognised
/// values is rejected as a validation error (rather than silently searching all kinds).
/// Hits come back ranked (score desc, then recency).
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

        // An empty/absent `kinds` array means "search every kind" (nil filter). But a
        // non-empty array whose values are ALL unrecognised is a caller error — silently
        // promoting a misspelled filter to an unfiltered search would surprise an agent
        // expecting a narrow result set, so reject it.
        var kinds: Set<ItemKind>?
        if let raw = args["kinds"]?.arrayValue, !raw.isEmpty {
            let parsed = raw.compactMap { $0.stringValue.flatMap(ItemKind.init(rawValue:)) }
            guard !parsed.isEmpty else {
                throw AgentError.validation("kinds contained no recognised ItemKind values")
            }
            kinds = Set(parsed)
        }

        let hits = await context.searchIndex.search(query, kinds: kinds, limit: limit)
        return .object(["results": try TasksToolJSON.encode(hits.map(SearchHitDTO.init(from:)))])
    }
}
