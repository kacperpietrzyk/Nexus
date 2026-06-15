import Foundation
import NexusCore

// MARK: - people.suggest_duplicates

/// Discovery counterpart to `people.merge` (dedup, spec §4.3): given a name/alias the
/// caller is about to add, suggest an existing live `Person` that already matches it
/// case/diacritic-insensitively. Read-only — never creates or mutates. Returns the
/// candidate (if any) under `matches` so the caller can decide whether to `people.merge`.
public struct PeopleSuggestDuplicatesTool: AgentTool {
    public let name = "people.suggest_duplicates"
    public let description =
        "Suggests an existing person whose name or alias matches the query "
        + "(case/diacritic-insensitive). Read-only — never creates or mutates. Use before adding a "
        + "contact to avoid duplicates, then pair with people.merge. Returns matches (empty if none)."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "query": .string(description: "Display name or alias to match against existing people.")
        ],
        required: ["query"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let query = try PeopleToolSupport.requiredString(args["query"], field: "query")
        guard let match = try context.personRepository.suggestExisting(matching: query) else {
            return .object(["matches": .array([])])
        }
        let dto = try TasksToolJSON.encode(PersonDTO(from: match))
        return .object(["matches": .array([dto])])
    }
}
