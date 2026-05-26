import Foundation
import NexusAgentTools
import NexusCore
import SwiftData

public struct AgentLinkItemsTool: MutatingAgentTool {
    public let name = "agent.link_items"
    public let description = "Create a Link between two Nexus items."
    public let inputSchema: JSONSchema = AgentLinkItemsArguments.inputSchema

    private let modelContext: ModelContextRef

    @MainActor
    public init(context: ModelContext) {
        self.modelContext = ModelContextRef(context)
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let input = try AgentLinkItemsArguments.input(from: args)
        let repository = LinkRepository(context: modelContext.context)
        let link = try repository.findOrCreate(
            from: (input.fromKind, input.fromID),
            to: (input.toKind, input.toID),
            linkKind: input.linkKind,
            order: input.order
        )

        return .object([
            "status": .string("ok"),
            "linkID": .string(link.id.uuidString),
            "idempotencyKey": .string(link.idempotencyKey),
        ])
    }

    @MainActor
    public func inverse(input: JSONValue, context: AgentContext) async throws -> InverseAction {
        let input = try AgentLinkItemsArguments.input(from: input)
        if try AgentLinkItemsArguments.existingLink(matching: input, in: modelContext.context) != nil {
            let noopInput: JSONValue = .object([
                "reason": .string("link_already_existed")
            ])
            return InverseAction(
                toolName: "agent.noop",
                inputJSON: try JSONEncoder().encode(noopInput)
            )
        }

        return InverseAction(
            toolName: "agent.unlink_items",
            inputJSON: try JSONEncoder().encode(AgentLinkItemsArguments.jsonValue(from: input))
        )
    }
}

public struct AgentNoopTool: AgentTool {
    public let name = "agent.noop"
    public let description = "Record a no-op tool result."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "reason": .string(description: "Machine-readable reason for the no-op.")
        ],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let object = try AgentMemoryToolArguments.object(from: args)
        let reason = try AgentMemoryToolArguments.optionalString(object["reason"], field: "reason")
        return .object([
            "status": .string("ok"),
            "reason": reason.map { .string($0) } ?? .null,
        ])
    }
}

public struct AgentUnlinkItemsTool: AgentTool {
    public let name = "agent.unlink_items"
    public let description = "Delete matching Links between two Nexus items."
    public let inputSchema: JSONSchema = AgentLinkItemsArguments.inputSchema

    private let modelContext: ModelContextRef

    @MainActor
    public init(context: ModelContext) {
        self.modelContext = ModelContextRef(context)
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let input = try AgentLinkItemsArguments.input(from: args)
        let matches = try AgentLinkItemsArguments.matchingLinks(
            input,
            in: modelContext.context
        )

        for link in matches {
            modelContext.context.delete(link)
        }
        if !matches.isEmpty {
            try modelContext.context.save()
        }

        return .object([
            "status": .string("ok"),
            "deletedCount": .int(matches.count),
        ])
    }
}

struct AgentLinkItemsInput: Equatable {
    let fromKind: ItemKind
    let fromID: UUID
    let toKind: ItemKind
    let toID: UUID
    let linkKind: LinkKind
    let order: Int?
}

enum AgentLinkItemsArguments {
    static let inputSchema: JSONSchema = .object(
        properties: [
            "fromKind": .string(
                enumValues: ItemKind.allCases.map(\.rawValue),
                description: "Source item kind."
            ),
            "fromID": .string(description: "Source item UUID."),
            "toKind": .string(
                enumValues: ItemKind.allCases.map(\.rawValue),
                description: "Target item kind."
            ),
            "toID": .string(description: "Target item UUID."),
            "linkKind": .string(
                enumValues: LinkKind.allCases.map(\.rawValue),
                description: "Link relationship kind."
            ),
            "order": .integer(description: "Optional ordering value."),
        ],
        required: ["fromKind", "fromID", "toKind", "toID", "linkKind"]
    )

    static func input(from args: JSONValue) throws -> AgentLinkItemsInput {
        let object = try AgentMemoryToolArguments.object(from: args)
        return AgentLinkItemsInput(
            fromKind: try itemKind(object["fromKind"], field: "fromKind"),
            fromID: try uuid(object["fromID"], field: "fromID"),
            toKind: try itemKind(object["toKind"], field: "toKind"),
            toID: try uuid(object["toID"], field: "toID"),
            linkKind: try linkKind(object["linkKind"], field: "linkKind"),
            order: try AgentMemoryToolArguments.optionalInt(object["order"], field: "order")
        )
    }

    static func jsonValue(from input: AgentLinkItemsInput) -> JSONValue {
        var object: [String: JSONValue] = [
            "fromKind": .string(input.fromKind.rawValue),
            "fromID": .string(input.fromID.uuidString),
            "toKind": .string(input.toKind.rawValue),
            "toID": .string(input.toID.uuidString),
            "linkKind": .string(input.linkKind.rawValue),
        ]
        if let order = input.order {
            object["order"] = .int(order)
        }
        return .object(object)
    }

    @MainActor
    static func existingLink(
        matching input: AgentLinkItemsInput,
        in context: ModelContext
    ) throws -> Link? {
        try matchingLinks(input, in: context).first
    }

    @MainActor
    static func matchingLinks(
        _ input: AgentLinkItemsInput,
        in context: ModelContext
    ) throws -> [Link] {
        let fromID = input.fromID
        let toID = input.toID
        let descriptor = FetchDescriptor<Link>(
            predicate: #Predicate { link in
                link.fromID == fromID && link.toID == toID
            }
        )
        return try context.fetch(descriptor).filter {
            $0.fromKind == input.fromKind && $0.toKind == input.toKind
                && $0.linkKind == input.linkKind
        }
    }

    private static func uuid(_ value: JSONValue?, field: String) throws -> UUID {
        let text = try AgentMemoryToolArguments.requiredString(value, field: field)
        guard let id = UUID(uuidString: text) else {
            throw AgentError.validation("\(field) must be a UUID string")
        }
        return id
    }

    private static func itemKind(_ value: JSONValue?, field: String) throws -> ItemKind {
        let rawValue = try AgentMemoryToolArguments.requiredString(value, field: field)
        guard let kind = ItemKind(rawValue: rawValue) else {
            throw AgentError.validation("Unknown \(field): \(rawValue)")
        }
        return kind
    }

    private static func linkKind(_ value: JSONValue?, field: String) throws -> LinkKind {
        let rawValue = try AgentMemoryToolArguments.requiredString(value, field: field)
        guard let kind = LinkKind(rawValue: rawValue) else {
            throw AgentError.validation("Unknown \(field): \(rawValue)")
        }
        return kind
    }
}
