import Foundation
import NexusCore

// MARK: - Shared support

enum SavedFiltersToolSupport {
    /// Decodes a free-form `definition` JSON object into the Codable
    /// `FilterDefinition`. Reuses the `TasksToolJSON` round-trip seam
    /// (`JSONValue → Data → JSONDecoder`) so the wire shape always matches
    /// `FilterDefinition`'s synthesized Codable encoding.
    static func parseDefinition(_ value: JSONValue?) throws -> FilterDefinition {
        guard let value else {
            throw AgentError.validation("Missing required field: definition")
        }
        do {
            return try TasksToolJSON.decode(FilterDefinition.self, from: value)
        } catch {
            throw AgentError.validation(
                "definition is not a valid filter definition: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    static func liveFilter(id: UUID, context: AgentContext) throws -> SavedFilter {
        guard let filter = try context.savedFilterRepository.find(id) else {
            throw AgentError.notFound("Saved filter not found: \(id.uuidString)")
        }
        return filter
    }
}

// MARK: - saved_filters.list

public struct SavedFiltersListTool: AgentTool {
    public let name = "saved_filters.list"
    public let description = "Lists active (non-deleted) saved filters in their stored order."
    public let inputSchema: JSONSchema = .object(properties: [:], required: [])

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let filters = try context.savedFilterRepository.all()
        return .object(["filters": try TasksToolJSON.encode(filters.map { SavedFilterDTO(from: $0) })])
    }
}

// MARK: - saved_filters.create

public struct SavedFiltersCreateTool: AgentTool {
    public let name = "saved_filters.create"
    public let description = """
        Creates a saved filter from a free-form FilterDefinition JSON object. \
        Returns the created saved-filter DTO.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "name": .string(description: "Saved filter name."),
            "definition": .anyValue(description: "FilterDefinition JSON object (Codable shape)."),
            "icon": .string(description: "Optional SF Symbol name for the filter."),
        ],
        required: ["name", "definition"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        let definition = try SavedFiltersToolSupport.parseDefinition(args["definition"])
        let icon = try ProjectsToolSupport.optionalTrimmedString(args["icon"], field: "icon")
        let filter: SavedFilter
        if let icon {
            filter = try context.savedFilterRepository.create(name: name, definition: definition, icon: icon)
        } else {
            filter = try context.savedFilterRepository.create(name: name, definition: definition)
        }
        return try TasksToolJSON.encode(SavedFilterDTO(from: filter))
    }
}

// MARK: - saved_filters.update

public struct SavedFiltersUpdateTool: AgentTool {
    public let name = "saved_filters.update"
    public let description = """
        Renames and/or replaces the FilterDefinition of a saved filter. \
        Returns the updated saved-filter DTO.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "filter_id": .string(description: "Saved filter UUID."),
            "name": .string(description: "Optional new name."),
            "definition": .anyValue(description: "Optional replacement FilterDefinition JSON object."),
        ],
        required: ["filter_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["filter_id"], field: "filter_id")
        let filter = try SavedFiltersToolSupport.liveFilter(id: id, context: context)
        let name = try ProjectsToolSupport.optionalTrimmedString(args["name"], field: "name")
        let definition = try args["definition"].map { try SavedFiltersToolSupport.parseDefinition($0) }
        try context.savedFilterRepository.update(filter, name: name, definition: definition)
        return try TasksToolJSON.encode(SavedFilterDTO(from: filter))
    }
}

// MARK: - saved_filters.delete

public struct SavedFiltersDeleteTool: AgentTool {
    public let name = "saved_filters.delete"
    public let description = "Soft-deletes a saved filter. Returns {id, deleted}."
    public let inputSchema: JSONSchema = .object(
        properties: ["filter_id": .string(description: "Saved filter UUID.")],
        required: ["filter_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["filter_id"], field: "filter_id")
        let filter = try SavedFiltersToolSupport.liveFilter(id: id, context: context)
        try context.savedFilterRepository.delete(filter)
        return .object(["id": .string(id.uuidString), "deleted": .bool(true)])
    }
}

// MARK: - saved_filters.apply

public struct SavedFiltersApplyTool: AgentTool {
    public let name = "saved_filters.apply"
    public let description = "Applies a saved filter and returns the matching open tasks as {tasks: [TaskDTO]}."
    public let inputSchema: JSONSchema = .object(
        properties: ["filter_id": .string(description: "Saved filter UUID.")],
        required: ["filter_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["filter_id"], field: "filter_id")
        let filter = try SavedFiltersToolSupport.liveFilter(id: id, context: context)
        let tasks = try context.savedFilterRepository.apply(filter, now: context.now())
        let dtos = try tasks.map { try TaskNotesContentStore.dto(for: $0, context: context) }
        return .object(["tasks": try TasksToolJSON.encode(dtos)])
    }
}
