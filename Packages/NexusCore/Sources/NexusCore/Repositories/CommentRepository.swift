import Foundation
import SwiftData

/// CRUD for `Comment`, scoped by the owning item id + kind. `@MainActor` to
/// match the SwiftData isolation used across the repositories.
@MainActor
public struct CommentRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Non-deleted comments for an item, oldest first.
    public func comments(for itemID: UUID, kind: ItemKind) throws -> [Comment] {
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.itemID == itemID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).filter { $0.itemKind == kind }
    }

    @discardableResult
    public func add(
        body: String,
        to itemID: UUID,
        kind: ItemKind,
        externalSourceID: String? = nil
    ) throws -> Comment {
        let comment = Comment(
            itemID: itemID,
            itemKind: kind,
            body: body,
            externalSourceID: externalSourceID
        )
        context.insert(comment)
        try context.save()
        return comment
    }

    public func edit(_ comment: Comment, body: String) throws {
        comment.body = body
        comment.updatedAt = .now
        try context.save()
    }

    public func softDelete(_ comment: Comment) throws {
        comment.deletedAt = .now
        try context.save()
    }

    /// Cascade helper: soft-delete every comment anchored to an item.
    /// Called from task/project delete paths.
    public func softDeleteAll(for itemID: UUID, kind: ItemKind) throws {
        for comment in try comments(for: itemID, kind: kind) {
            comment.deletedAt = .now
        }
        try context.save()
    }

    /// Fetch a single non-deleted comment by id, or nil.
    public func find(_ id: UUID) throws -> Comment? {
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        return try context.fetch(descriptor).first
    }
}
