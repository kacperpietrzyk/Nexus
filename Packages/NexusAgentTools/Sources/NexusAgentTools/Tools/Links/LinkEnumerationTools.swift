import Foundation
import NexusCore
import SwiftData

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
        return try LinkToolSupport.encode(Array(context.linkRepository.allLinks().dedupedByID().prefix(limit)))
    }
}

/// One-shot idempotent backfill: reclassify semantically wrong `child` edges from notes/meetings
/// to projects as `relatedProject`. Safe to run multiple times — a second pass finds nothing and
/// returns `reclassified_count: 0`.
public struct LinksReclassifyProjectMembershipTool: AgentTool {
    public let name = "links.reclassify_project_membership"
    public let description =
        "Idempotent backfill that reclassifies incorrect `.child` edges from notes or meetings to "
        + "projects as the canonical `.relatedProject` kind. Optionally scoped to a single project "
        + "via `project_id`. Task→task `.child` edges and all other link kinds are never touched. "
        + "Safe to run multiple times — subsequent runs return `reclassified_count: 0`."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(
                description: "Optional UUID of a specific project. When provided, only edges whose "
                    + "target is that project are reclassified. Omit to reclassify across all projects."
            )
        ],
        required: []
    )
    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let modelContext = context.modelContext.context

        // Parse optional project_id scope.
        let scopeID: UUID?
        if let raw = args["project_id"]?.stringValue {
            guard let id = UUID(uuidString: raw) else {
                throw AgentError.validation("project_id must be a valid UUID string")
            }
            scopeID = id
        } else {
            scopeID = nil
        }

        // Fetch all Link rows from the shared context so mutations persist.
        let descriptor = FetchDescriptor<Link>()
        let allLinks = try modelContext.fetch(descriptor)

        // Filter: child edges FROM note|meeting TO project (optionally scoped).
        let targets = allLinks.filter { link in
            link.linkKind == .child
                && link.toKind == .project
                && (link.fromKind == .note || link.fromKind == .meeting)
                && (scopeID == nil || link.toID == scopeID!)
        }

        // Mutate in-place; all objects share the same context — one save is enough.
        for link in targets {
            link.linkKind = .relatedProject
        }

        if !targets.isEmpty {
            try modelContext.save()
        }

        return .object(["reclassified_count": .int(targets.count)])
    }
}
