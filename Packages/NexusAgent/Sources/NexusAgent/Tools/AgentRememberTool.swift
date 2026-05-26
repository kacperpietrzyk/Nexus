import Foundation
import NexusAgentTools
import NexusCore

public struct AgentRememberTool: MutatingAgentTool {
    public let name = "agent.remember"
    public let description = "Upsert an agent memory entry keyed by scope and key."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "scope": .string(description: "Memory namespace, for example global or project:<id>."),
            "key": .string(description: "Stable key within the scope."),
            "content": .string(description: "Memory content to persist."),
            "confidence": .number(description: "Optional confidence score. Defaults to 1.0."),
            "linkedItemIDs": .array(
                items: .string(description: "Linked item UUID."),
                description: "Optional related item UUIDs."
            ),
        ],
        required: ["scope", "key", "content"]
    )

    private let storeRef: AgentMemoryStoreRef

    public init(store: AgentMemoryStore) {
        self.storeRef = AgentMemoryStoreRef(store)
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let input = try AgentMemoryToolArguments.rememberInput(from: args)
        let id = try storeRef.store.upsert(
            scope: input.scope,
            key: input.key,
            content: input.content,
            confidence: input.confidence,
            linkedItemIDs: input.linkedItemIDs
        )
        return .object([
            "status": .string("ok"),
            "id": .string(id.uuidString),
        ])
    }

    @MainActor
    public func inverse(input: JSONValue, context: AgentContext) async throws -> InverseAction {
        let input = try AgentMemoryToolArguments.rememberInput(from: input)
        if let existing = try storeRef.store.find(scope: input.scope, key: input.key) {
            let restoreInput = JSONValue.object([
                "scope": .string(existing.scope),
                "key": .string(existing.key),
                "content": .string(existing.content),
                "confidence": .double(existing.confidence),
                "linkedItemIDs": .array(existing.linkedItemIDs.map { .string($0.uuidString) }),
            ])
            return InverseAction(
                toolName: "agent.remember",
                inputJSON: try JSONEncoder().encode(restoreInput)
            )
        }

        let forgetInput: JSONValue = .object([
            "scope": .string(input.scope),
            "key": .string(input.key),
        ])
        return InverseAction(
            toolName: "agent.forget",
            inputJSON: try JSONEncoder().encode(forgetInput)
        )
    }
}

public struct AgentForgetTool: AgentTool {
    public let name = "agent.forget"
    public let description = "Delete an agent memory entry by scope and key."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "scope": .string(description: "Memory namespace."),
            "key": .string(description: "Stable key within the scope."),
        ],
        required: ["scope", "key"]
    )

    private let storeRef: AgentMemoryStoreRef

    public init(store: AgentMemoryStore) {
        self.storeRef = AgentMemoryStoreRef(store)
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let input = try AgentMemoryToolArguments.forgetInput(from: args)
        if let entry = try storeRef.store.find(scope: input.scope, key: input.key) {
            try storeRef.store.delete(id: entry.id)
        }
        return .object(["status": .string("ok")])
    }
}

struct AgentRememberInput: Equatable {
    let scope: String
    let key: String
    let content: String
    let confidence: Double
    let linkedItemIDs: [UUID]
}

struct AgentForgetInput: Equatable {
    let scope: String
    let key: String
}

enum AgentMemoryToolArguments {
    static func rememberInput(from args: JSONValue) throws -> AgentRememberInput {
        let object = try object(from: args)
        return AgentRememberInput(
            scope: try requiredString(object["scope"], field: "scope"),
            key: try requiredString(object["key"], field: "key"),
            content: try requiredString(object["content"], field: "content"),
            confidence: try optionalNumber(object["confidence"], field: "confidence") ?? 1.0,
            linkedItemIDs: try optionalUUIDArray(object["linkedItemIDs"], field: "linkedItemIDs")
        )
    }

    static func forgetInput(from args: JSONValue) throws -> AgentForgetInput {
        let object = try object(from: args)
        return AgentForgetInput(
            scope: try requiredString(object["scope"], field: "scope"),
            key: try requiredString(object["key"], field: "key")
        )
    }

    static func object(from args: JSONValue) throws -> [String: JSONValue] {
        guard let object = args.objectValue else {
            throw AgentError.validation("Input must be an object")
        }
        return object
    }

    static func requiredString(_ value: JSONValue?, field: String) throws -> String {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required string field: \(field)")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.validation("\(field) cannot be empty")
        }
        return trimmed
    }

    static func optionalString(_ value: JSONValue?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be a string")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.validation("\(field) cannot be empty")
        }
        return trimmed
    }

    static func optionalNumber(_ value: JSONValue?, field: String) throws -> Double? {
        guard let value else { return nil }
        guard let number = value.doubleValue else {
            throw AgentError.validation("\(field) must be a number")
        }
        return number
    }

    static func optionalInt(_ value: JSONValue?, field: String) throws -> Int? {
        guard let value else { return nil }
        guard let intValue = value.intValue else {
            throw AgentError.validation("\(field) must be an integer")
        }
        return intValue
    }

    static func optionalUUIDArray(_ value: JSONValue?, field: String) throws -> [UUID] {
        guard let value else { return [] }
        guard let values = value.arrayValue else {
            throw AgentError.validation("\(field) must be an array of UUID strings")
        }
        return try values.enumerated().map { index, value in
            guard let text = value.stringValue, let id = UUID(uuidString: text) else {
                throw AgentError.validation("\(field)[\(index)] must be a UUID string")
            }
            return id
        }
    }
}

final class AgentMemoryStoreRef: @unchecked Sendable {
    let store: AgentMemoryStore

    init(_ store: AgentMemoryStore) {
        self.store = store
    }
}
