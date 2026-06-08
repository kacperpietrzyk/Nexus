import Foundation
import NexusCore

// MARK: - blocks.list

/// Reads the dependency edges for a task or project (spec §9): the items it blocks
/// (outgoing) and the items that block it (`blocked_by` = incoming).
public struct BlocksListTool: AgentTool {
    public let name = "blocks.list"
    public let description = """
        Lists dependency edges for a task or project: the items it blocks (outgoing) \
        and the items that block it (blocked_by, incoming).
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "item_id": .string(description: "Task or project UUID."),
            "item_kind": .string(enumValues: ["task", "project"], description: "task | project"),
        ],
        required: ["item_id", "item_kind"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let (id, endpoint) = try ProjectsToolSupport.parseEndpoint(args)
        let from = (endpoint.endpointItemKind, id)
        let outgoing = try context.linkRepository.outgoingBlocks(from: from)
        let incoming = try context.linkRepository.incomingBlocks(to: from)
        let dto = BlocksDTO(
            blocks: outgoing.map { EndpointRefDTO(kind: $0.toKind.rawValue, id: $0.toID.uuidString) },
            blockedBy: incoming.map { EndpointRefDTO(kind: $0.fromKind.rawValue, id: $0.fromID.uuidString) }
        )
        return try TasksToolJSON.encode(dto)
    }
}

// MARK: - blocks.add

/// Adds a `blocks` edge: `from` blocks `to` (spec §9). Idempotent on the edge.
/// Returns the `from` endpoint's resulting dependency view.
public struct BlocksAddTool: AgentTool {
    public let name = "blocks.add"
    public let description = """
        Adds a dependency edge where one item blocks another (from blocks to). \
        Endpoints are tasks or projects. Idempotent. Returns the from endpoint's \
        resulting dependency view.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "from_id": .string(description: "Blocking item UUID."),
            "from_kind": .string(enumValues: ["task", "project"], description: "task | project"),
            "to_id": .string(description: "Blocked item UUID."),
            "to_kind": .string(enumValues: ["task", "project"], description: "task | project"),
        ],
        required: ["from_id", "from_kind", "to_id", "to_kind"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let from = try BlocksToolSupport.endpoint(args, idField: "from_id", kindField: "from_kind")
        let to = try BlocksToolSupport.endpoint(args, idField: "to_id", kindField: "to_kind")
        if from == to {
            throw AgentError.validation("A blocks edge cannot point an item at itself")
        }
        try context.linkRepository.findOrCreate(from: from, to: to, linkKind: .blocks)
        return try BlocksToolSupport.dependencyView(for: from, context: context)
    }
}

// MARK: - blocks.remove

/// Removes the `blocks` edge from `from` to `to` (spec §9). Returns the `from`
/// endpoint's resulting dependency view.
public struct BlocksRemoveTool: AgentTool {
    public let name = "blocks.remove"
    public let description = """
        Removes a dependency edge (from blocks to). Returns the from endpoint's \
        resulting dependency view.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "from_id": .string(description: "Blocking item UUID."),
            "from_kind": .string(enumValues: ["task", "project"], description: "task | project"),
            "to_id": .string(description: "Blocked item UUID."),
            "to_kind": .string(enumValues: ["task", "project"], description: "task | project"),
        ],
        required: ["from_id", "from_kind", "to_id", "to_kind"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let from = try BlocksToolSupport.endpoint(args, idField: "from_id", kindField: "from_kind")
        let to = try BlocksToolSupport.endpoint(args, idField: "to_id", kindField: "to_kind")
        for edge in try context.linkRepository.outgoingBlocks(from: from)
        where edge.toID == to.1 && edge.toKind == to.0 {
            try context.linkRepository.delete(edge)
        }
        return try BlocksToolSupport.dependencyView(for: from, context: context)
    }
}

// MARK: - support

enum BlocksToolSupport {
    static func endpoint(_ args: JSONValue, idField: String, kindField: String) throws -> (ItemKind, UUID) {
        let id = try TasksToolArguments.requiredUUID(args[idField], field: idField)
        let kindText = try TasksToolArguments.requiredString(args[kindField], field: kindField)
        switch kindText {
        case "task": return (.task, id)
        case "project": return (.project, id)
        default: throw AgentError.validation("\(kindField) must be 'task' or 'project'")
        }
    }

    @MainActor
    static func dependencyView(for from: (ItemKind, UUID), context: AgentContext) throws -> JSONValue {
        let outgoing = try context.linkRepository.outgoingBlocks(from: from)
        let incoming = try context.linkRepository.incomingBlocks(to: from)
        let dto = BlocksDTO(
            blocks: outgoing.map { EndpointRefDTO(kind: $0.toKind.rawValue, id: $0.toID.uuidString) },
            blockedBy: incoming.map { EndpointRefDTO(kind: $0.fromKind.rawValue, id: $0.fromID.uuidString) }
        )
        return try TasksToolJSON.encode(dto)
    }
}
