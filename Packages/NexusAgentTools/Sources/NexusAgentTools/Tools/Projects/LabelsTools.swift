import Foundation
import NexusCore

// MARK: - labels.list_all

/// Lists every active (non-soft-deleted) label in the system (spec §7).
public struct LabelsListAllTool: AgentTool {
    public let name = "labels.list_all"
    public let description = "Lists all active labels (system + user-created), sorted by name."
    public let inputSchema: JSONSchema = .object(properties: [:], required: [])

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let labels = try context.labelRepository.allActive()
        return try TasksToolJSON.encode(labels.map { LabelDTO(from: $0) })
    }
}

// MARK: - labels.list_for

/// Lists the labels attached to a task or project endpoint (spec §7).
public struct LabelsListForTool: AgentTool {
    public let name = "labels.list_for"
    public let description = "Lists the labels attached to a task or project."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "item_id": .string(description: "Owning task or project UUID."),
            "item_kind": .string(enumValues: ["task", "project"], description: "task | project"),
        ],
        required: ["item_id", "item_kind"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let (id, endpoint) = try ProjectsToolSupport.parseEndpoint(args)
        let labels = try context.labelRepository.labels(for: (endpoint, id))
        return try TasksToolJSON.encode(labels.map { LabelDTO(from: $0) })
    }
}

// MARK: - labels.assign

/// Assigns a label to a task or project (spec §7). Single-select for `domain`/`gate`
/// is enforced by `LabelRepository.assign` (invariant I5): assigning a domain/gate
/// label removes any prior label of the same group from the endpoint. Returns the
/// resulting label set on the endpoint.
public struct LabelsAssignTool: AgentTool {
    public let name = "labels.assign"
    public let description = """
        Attaches an existing label to a task or project. Domain and gate labels are \
        single-select per endpoint: assigning one removes any prior label of the same \
        group. Free labels accumulate. Returns the endpoint's resulting labels.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "item_id": .string(description: "Owning task or project UUID."),
            "item_kind": .string(enumValues: ["task", "project"], description: "task | project"),
            "label_id": .string(description: "Label UUID to assign."),
        ],
        required: ["item_id", "item_kind", "label_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let (id, endpoint) = try ProjectsToolSupport.parseEndpoint(args)
        let labelID = try TasksToolArguments.requiredUUID(args["label_id"], field: "label_id")
        guard let label = try context.labelRepository.find(id: labelID), label.deletedAt == nil else {
            throw AgentError.notFound("Label not found: \(labelID.uuidString)")
        }
        try AgentEndpointValidator.validateLive(endpoint.endpointItemKind, id, context: context)
        try context.labelRepository.assign(label, to: (endpoint, id))
        let labels = try context.labelRepository.labels(for: (endpoint, id))
        return try TasksToolJSON.encode(labels.map { LabelDTO(from: $0) })
    }
}

// MARK: - labels.remove

/// Removes a label from a task or project by deleting the `.labeled` edge (spec §7).
/// The `Label` row is untouched (labels are shared). Returns the resulting label set.
public struct LabelsRemoveTool: AgentTool {
    public let name = "labels.remove"
    public let description = "Detaches a label from a task or project. Returns the endpoint's resulting labels."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "item_id": .string(description: "Owning task or project UUID."),
            "item_kind": .string(enumValues: ["task", "project"], description: "task | project"),
            "label_id": .string(description: "Label UUID to remove."),
        ],
        required: ["item_id", "item_kind", "label_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let (id, endpoint) = try ProjectsToolSupport.parseEndpoint(args)
        let labelID = try TasksToolArguments.requiredUUID(args["label_id"], field: "label_id")
        guard let label = try context.labelRepository.find(id: labelID) else {
            throw AgentError.notFound("Label not found: \(labelID.uuidString)")
        }
        try context.labelRepository.remove(label, from: (endpoint, id))
        let labels = try context.labelRepository.labels(for: (endpoint, id))
        return try TasksToolJSON.encode(labels.map { LabelDTO(from: $0) })
    }
}

// MARK: - Guard

/// Throws `.validation` if a label is system-owned or not in the `.free` group —
/// agents own only the free taxonomy (protects the seeded `SystemLabel` set:
/// domain/gate labels and any `isSystem` row).
@MainActor
func requireUserLabel(_ label: Label) throws {
    if label.isSystem || label.group != .free {
        throw AgentError.validation(
            "Label '\(label.name)' is a system/\(label.group.rawValue) label and cannot be modified by "
                + "agents. Agents manage free labels only."
        )
    }
}

// MARK: - labels.create

/// Creates a new free (user) label (spec §7). System and gate/domain groups are
/// reserved for the seeded `SystemLabel` set and are not creatable via MCP.
public struct LabelsCreateTool: AgentTool {
    public let name = "labels.create"
    public let description = "Creates a new free (user) label. System and gate/domain groups are not creatable via MCP."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "name": .string(description: "Label name."),
            "glyph_key": .string(description: "Optional achromatic glyph key."),
        ],
        required: ["name"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        let glyph = try ProjectsToolSupport.optionalTrimmedString(args["glyph_key"], field: "glyph_key") ?? ""
        let label = try context.labelRepository.create(name: name, glyphKey: glyph, group: .free, isSystem: false)
        return try TasksToolJSON.encode(LabelDTO(from: label))
    }
}

// MARK: - labels.update

/// Renames an existing free (user) label (spec §7). Rejects system/domain/gate
/// labels via `requireUserLabel`. Returns the updated label.
public struct LabelsUpdateTool: AgentTool {
    public let name = "labels.update"
    public let description = "Renames a free (user) label. System and gate/domain labels cannot be modified via MCP."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "label_id": .string(description: "Label UUID to rename."),
            "name": .string(description: "New label name."),
        ],
        required: ["label_id", "name"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let labelID = try TasksToolArguments.requiredUUID(args["label_id"], field: "label_id")
        guard let label = try context.labelRepository.find(id: labelID), label.deletedAt == nil else {
            throw AgentError.notFound("Label not found: \(labelID.uuidString)")
        }
        try requireUserLabel(label)
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        try context.labelRepository.rename(label, to: name)
        return try TasksToolJSON.encode(LabelDTO(from: label))
    }
}

// MARK: - labels.delete

/// Soft-deletes a free (user) label (spec §7). Rejects system/domain/gate labels
/// via `requireUserLabel`. The `.labeled` edges are untouched (readers filter
/// soft-deleted labels out). Returns `{id, deleted: true}`.
public struct LabelsDeleteTool: AgentTool {
    public let name = "labels.delete"
    public let description = "Soft-deletes a free (user) label. System and gate/domain labels cannot be deleted via MCP."
    public let inputSchema: JSONSchema = .object(
        properties: ["label_id": .string(description: "Label UUID to delete.")],
        required: ["label_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let labelID = try TasksToolArguments.requiredUUID(args["label_id"], field: "label_id")
        guard let label = try context.labelRepository.find(id: labelID), label.deletedAt == nil else {
            throw AgentError.notFound("Label not found: \(labelID.uuidString)")
        }
        try requireUserLabel(label)
        try context.labelRepository.softDelete(label)
        return .object(["id": .string(label.id.uuidString), "deleted": .bool(true)])
    }
}
