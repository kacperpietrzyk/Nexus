import Foundation
import NexusCore
import SwiftData

/// DTO for a single soft-deleted (trashed) item surfaced by `items.list_deleted`.
private struct DeletedItemDTO: Codable, Sendable, Equatable {
    let id: String
    let kind: String
    let title: String
    let deletedAt: String?
    private enum CodingKeys: String, CodingKey {
        case id, kind, title
        case deletedAt = "deleted_at"
    }
}

private enum TrashSupport {
    /// Kinds whose concrete model is `Linkable` and exposed via a per-kind repo, so a
    /// generic undelete (`LinkableRepository.restore`) is sound. `scheduledBlock`,
    /// `comment`, `meeting`, `section`, … are deliberately excluded.
    static let restorableKinds: [ItemKind] = [.task, .note, .project, .person, .organization, .cycle, .label]

    static func kind(from args: JSONValue, field: String) throws -> ItemKind {
        let raw = try TasksToolArguments.requiredString(args[field], field: field)
        guard let kind = ItemKind(rawValue: raw) else { throw AgentError.validation("Invalid kind: \(raw)") }
        guard restorableKinds.contains(kind) else { throw AgentError.validation("Kind not restorable via MCP: \(raw)") }
        return kind
    }

    static func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// `items.list_deleted` — fetch soft-deleted rows of a single kind so they can be restored.
public struct ItemsListDeletedTool: AgentTool {
    public let name = "items.list_deleted"
    public let description = "List soft-deleted (trashed) items of a given kind so they can be restored."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "kind": .string(
                enumValues: TrashSupport.restorableKinds.map(\.rawValue),
                description: "ItemKind to list from trash."
            ),
            "limit": .integer(minimum: 1, maximum: 500, description: "Max items (default 100)."),
        ],
        required: ["kind"]
    )
    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let kind = try TrashSupport.kind(from: args, field: "kind")
        let limit = try TasksToolArguments.boundedInt(args["limit"], field: "limit", default: 100, range: 1...500)
        let ctx = context.modelContext.context

        func dtos<Model: PersistentModel>(
            _: Model.Type,
            title: (Model) -> String,
            deleted: (Model) -> Date?,
            isDeleted: (Model) -> Bool,
            id: (Model) -> UUID
        ) throws -> [DeletedItemDTO] {
            try ctx.fetch(FetchDescriptor<Model>())
                .filter(isDeleted)
                .prefix(limit)
                .map {
                    DeletedItemDTO(
                        id: id($0).uuidString,
                        kind: kind.rawValue,
                        title: title($0),
                        deletedAt: TrashSupport.iso(deleted($0))
                    )
                }
        }

        let items: [DeletedItemDTO]
        switch kind {
        case .task:
            items = try dtos(TaskItem.self, title: \.title, deleted: \.deletedAt, isDeleted: { $0.deletedAt != nil }, id: \.id)
        case .note:
            items = try dtos(Note.self, title: \.title, deleted: \.deletedAt, isDeleted: { $0.deletedAt != nil }, id: \.id)
        case .project:
            items = try dtos(Project.self, title: \.name, deleted: \.deletedAt, isDeleted: { $0.deletedAt != nil }, id: \.id)
        case .person:
            items = try dtos(Person.self, title: \.displayName, deleted: \.deletedAt, isDeleted: { $0.deletedAt != nil }, id: \.id)
        case .organization:
            items = try dtos(Organization.self, title: \.name, deleted: \.deletedAt, isDeleted: { $0.deletedAt != nil }, id: \.id)
        case .cycle:
            items = try dtos(Cycle.self, title: \.name, deleted: \.deletedAt, isDeleted: { $0.deletedAt != nil }, id: \.id)
        case .label:
            items = try dtos(Label.self, title: \.name, deleted: \.deletedAt, isDeleted: { $0.deletedAt != nil }, id: \.id)
        default:
            throw AgentError.validation("Kind not restorable: \(kind.rawValue)")
        }

        return try .object(["items": TasksToolJSON.encode(items)])
    }
}

/// `items.restore` — undelete a soft-deleted item by id and kind.
public struct ItemsRestoreTool: AgentTool {
    public let name = "items.restore"
    public let description = "Restore a soft-deleted item (undelete) by id and kind."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "id": .string(description: "UUID of the soft-deleted item."),
            "kind": .string(
                enumValues: TrashSupport.restorableKinds.map(\.rawValue),
                description: "ItemKind of the item to restore."
            ),
        ],
        required: ["id", "kind"]
    )
    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["id"], field: "id")
        let kind = try TrashSupport.kind(from: args, field: "kind")
        let ctx = context.modelContext.context
        let searchIndex = context.searchIndex

        // The concrete per-kind repos don't expose `restore` (only `softDelete`); the canonical
        // undelete lives on the generic `LinkableRepository`. Every restorable kind's model is
        // `Linkable`, so a fresh `LinkableRepository<Model>` wired with the live `SearchIndex`
        // observer gives the real undelete (deletedAt = nil, updatedAt bumped, save) plus a
        // search-index re-index — matching the search behaviour of an in-app restore.
        func restore<Model: Linkable>(_: Model.Type, idOf: (Model) -> UUID) throws {
            guard let item = try ctx.fetch(FetchDescriptor<Model>()).first(where: { idOf($0) == id }) else {
                throw AgentError.notFound("\(kind.rawValue) not found: \(id.uuidString)")
            }
            try LinkableRepository(context: ctx, observers: [searchIndex]).restore(item)
        }

        switch kind {
        case .task: try restore(TaskItem.self, idOf: \.id)
        case .note: try restore(Note.self, idOf: \.id)
        case .project: try restore(Project.self, idOf: \.id)
        case .person: try restore(Person.self, idOf: \.id)
        case .organization: try restore(Organization.self, idOf: \.id)
        case .cycle: try restore(Cycle.self, idOf: \.id)
        case .label: try restore(Label.self, idOf: \.id)
        default: throw AgentError.validation("Kind not restorable: \(kind.rawValue)")
        }

        return .object(["success": .bool(true)])
    }
}
