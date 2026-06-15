import Foundation
import NexusCore

private enum LinkToolSupport {
    static func endpoint(from args: JSONValue) throws -> (ItemKind, UUID) {
        let id = try TasksToolArguments.requiredUUID(args["endpoint_id"], field: "endpoint_id")
        let kindRaw = try TasksToolArguments.requiredString(args["endpoint_kind"], field: "endpoint_kind")
        guard let kind = ItemKind(rawValue: kindRaw) else {
            throw AgentError.validation("Invalid endpoint_kind: \(kindRaw)")
        }
        return (kind, id)
    }

    static let endpointSchema: JSONSchema = .object(
        properties: [
            "endpoint_id": .string(description: "UUID of the endpoint item."),
            "endpoint_kind": .string(
                enumValues: ItemKind.allCases.map(\.rawValue),
                description: "ItemKind of the endpoint (e.g. task, note, person)."
            ),
        ],
        required: ["endpoint_id", "endpoint_kind"]
    )

    static func encode(_ links: [Link]) throws -> JSONValue {
        try .object(["links": TasksToolJSON.encode(links.map(LinkDTO.init(from:)))])
    }
}

public struct LinksBacklinksTool: AgentTool {
    public let name = "links.backlinks"
    public let description = "List every link edge pointing TO the given endpoint (incoming backlinks)."
    public let inputSchema = LinkToolSupport.endpointSchema
    public init() {}
    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let endpoint = try LinkToolSupport.endpoint(from: args)
        return try LinkToolSupport.encode(context.linkRepository.backlinks(to: endpoint))
    }
}

public struct LinksOutgoingTool: AgentTool {
    public let name = "links.outgoing"
    public let description = "List every link edge originating FROM the given endpoint (outgoing edges)."
    public let inputSchema = LinkToolSupport.endpointSchema
    public init() {}
    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let endpoint = try LinkToolSupport.endpoint(from: args)
        return try LinkToolSupport.encode(context.linkRepository.outgoing(from: endpoint))
    }
}

public struct LinksListTool: AgentTool {
    public let name = "links.list"
    public let description = "Dump the whole link graph (every edge, oldest first). For audit / graph export."
    public let inputSchema: JSONSchema = .object(
        properties: ["limit": .integer(minimum: 1, maximum: 5000, description: "Max edges to return (default 1000).")],
        required: []
    )
    public init() {}
    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let limit = try TasksToolArguments.boundedInt(args["limit"], field: "limit", default: 1000, range: 1...5000)
        return try LinkToolSupport.encode(Array(context.linkRepository.allLinks().prefix(limit)))
    }
}
