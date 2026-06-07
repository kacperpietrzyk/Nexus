import Foundation
import NexusCore

// MARK: - Shared helpers

private func parseItem(_ args: JSONValue) throws -> (UUID, ItemKind) {
    guard let idText = args["item_id"]?.stringValue, let id = UUID(uuidString: idText) else {
        throw AgentError.validation("item_id must be a valid UUID")
    }
    guard
        let kindText = args["item_kind"]?.stringValue,
        let kind = ItemKind(rawValue: kindText),
        kind == .task || kind == .project
    else {
        throw AgentError.validation("item_kind must be 'task' or 'project'")
    }
    return (id, kind)
}

// MARK: - comments.list

public struct CommentsListTool: AgentTool {
    public let name = "comments.list"
    public let description = "Lists comments for a task or project, oldest first."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "item_id": .string(description: "Owning task or project UUID."),
            "item_kind": .string(description: "task | project"),
        ],
        required: ["item_id", "item_kind"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let (id, kind) = try parseItem(args)
        let comments = try context.commentRepository.comments(for: id, kind: kind)
        return try TasksToolJSON.encode(comments.map { CommentDTO(from: $0) })
    }
}

// MARK: - comments.add

public struct CommentsAddTool: AgentTool {
    public let name = "comments.add"
    public let description = "Adds a comment to a task or project."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "item_id": .string(description: "Owning task or project UUID."),
            "item_kind": .string(description: "task | project"),
            "body": .string(description: "Comment text."),
            "external_source_id": .string(description: "Optional idempotent import key."),
        ],
        required: ["item_id", "item_kind", "body"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let (id, kind) = try parseItem(args)
        guard
            let body = args["body"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !body.isEmpty
        else {
            throw AgentError.validation("body cannot be empty")
        }
        let external = args["external_source_id"]?.stringValue
        let comment = try context.commentRepository.add(body: body, to: id, kind: kind, externalSourceID: external)
        return try TasksToolJSON.encode(CommentDTO(from: comment))
    }
}

// MARK: - comments.edit

public struct CommentsEditTool: AgentTool {
    public let name = "comments.edit"
    public let description = "Edits a comment's body."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "id": .string(description: "Comment UUID."),
            "body": .string(description: "New text."),
        ],
        required: ["id", "body"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        guard let idText = args["id"]?.stringValue, let id = UUID(uuidString: idText) else {
            throw AgentError.validation("id must be a valid UUID")
        }
        guard let body = args["body"]?.stringValue else {
            throw AgentError.validation("body required")
        }
        guard let comment = try context.commentRepository.find(id) else {
            throw AgentError.notFound("comment not found: \(idText)")
        }
        try context.commentRepository.edit(comment, body: body)
        return try TasksToolJSON.encode(CommentDTO(from: comment))
    }
}

// MARK: - comments.delete

public struct CommentsDeleteTool: AgentTool {
    public let name = "comments.delete"
    public let description = "Soft-deletes a comment."
    public let inputSchema: JSONSchema = .object(
        properties: ["id": .string(description: "Comment UUID.")],
        required: ["id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        guard let idText = args["id"]?.stringValue, let id = UUID(uuidString: idText) else {
            throw AgentError.validation("id must be a valid UUID")
        }
        guard let comment = try context.commentRepository.find(id) else {
            throw AgentError.notFound("comment not found: \(idText)")
        }
        try context.commentRepository.softDelete(comment)
        return .object(["deleted": .bool(true)])
    }
}
