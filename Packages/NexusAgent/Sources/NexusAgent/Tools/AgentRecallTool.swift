import Foundation
import NexusAgentTools
import NexusCore

public struct AgentRecallTool: AgentTool {
    public let name = "agent.recall"
    public let description = "Return matching agent memory entries."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "scope": .string(description: "Memory namespace. Defaults to global."),
            "key": .string(description: "Optional exact key filter."),
            "query": .string(description: "Optional case-insensitive content search."),
            "limit": .integer(
                minimum: 0,
                maximum: 1_000,
                description: "Maximum entries to return. Defaults to 10."
            ),
        ],
        required: []
    )

    private let storeRef: AgentMemoryStoreRef

    public init(store: AgentMemoryStore) {
        self.storeRef = AgentMemoryStoreRef(store)
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let input = try AgentRecallArguments.input(from: args)
        guard input.limit > 0 else {
            return .object(["entries": .array([])])
        }

        var entries = try storeRef.store.list(scope: input.scope)
        if let key = input.key {
            entries = entries.filter { $0.key == key }
        }
        if let query = input.query?.lowercased() {
            entries = entries.filter { $0.content.lowercased().contains(query) }
        }

        let encoded = entries.prefix(input.limit).map { entry in
            JSONValue.object([
                "id": .string(entry.id.uuidString),
                "scope": .string(entry.scope),
                "key": .string(entry.key),
                "content": .string(entry.content),
                "confidence": .double(entry.confidence),
                "updatedAt": .string(Self.iso8601String(from: entry.updatedAt)),
            ])
        }
        return .object(["entries": .array(Array(encoded))])
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

struct AgentRecallInput: Equatable {
    let scope: String
    let key: String?
    let query: String?
    let limit: Int
}

enum AgentRecallArguments {
    static func input(from args: JSONValue) throws -> AgentRecallInput {
        let object = try AgentMemoryToolArguments.object(from: args)
        let limit = try AgentMemoryToolArguments.optionalInt(object["limit"], field: "limit") ?? 10
        guard limit <= 1_000 else {
            throw AgentError.validation("limit must be between 0 and 1000")
        }
        return AgentRecallInput(
            scope: try AgentMemoryToolArguments.optionalString(object["scope"], field: "scope")
                ?? "global",
            key: try AgentMemoryToolArguments.optionalString(object["key"], field: "key"),
            query: try AgentMemoryToolArguments.optionalString(object["query"], field: "query"),
            limit: limit
        )
    }
}
