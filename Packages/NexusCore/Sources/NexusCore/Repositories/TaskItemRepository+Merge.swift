import Foundation
import SwiftData

public enum TaskMergeError: Error, Equatable {
    case cannotMergeIntoSelf(taskID: UUID)
    case sourceAlreadyDeleted(taskID: UUID)
}

// MARK: - tasks.merge

@MainActor
extension TaskItemRepository {
    /// Atomically merges a duplicate task (`from`) into a survivor (`into`):
    /// repoints every graph `Link` endpoint, unions tags, fills empty survivor fields,
    /// carries the earlier `createdAt`, and soft-deletes the loser. Mirrors
    /// `PersonRepository.mergePeople(into:from:)`.
    ///
    /// All mutations run on one `ModelContext` and commit via a single terminal
    /// `context.save()`. Edge repointing mutates `Link` endpoints directly rather
    /// than routing through `LinkRepository` (whose `findOrCreate`/`delete` each
    /// save), so a throw before the terminal save leaves nothing persisted —
    /// no orphaned edge (I2). Throws (saving nothing) if `from` and `into` are
    /// the same task or `from` is already deleted.
    ///
    /// **Known limitation:** `parentTaskID` (task hierarchy) is a scalar pointer,
    /// not a `Link`, so subtasks of the loser keep pointing at the tombstoned
    /// parent after merge. They become orphaned until the user reassigns them.
    /// This mirrors the `people.merge` scope — Link graph only — and is documented
    /// as a follow-up.
    public func mergeTasks(into: TaskItem, from: TaskItem) throws {
        guard into.id != from.id else {
            throw TaskMergeError.cannotMergeIntoSelf(taskID: from.id)
        }
        guard from.deletedAt == nil else {
            throw TaskMergeError.sourceAlreadyDeleted(taskID: from.id)
        }
        let stamp = now()

        // 1. Repoint edges (incoming + outgoing, deduped). 2. Union tags. 3. Fill fields.
        try repointEdges(from: from.id, into: into.id)
        into.tags = Self.normalize(tags: into.tags + from.tags)
        fillEmptyFields(into: into, from: from)

        // 4. Carry the earlier `createdAt`.
        if from.createdAt < into.createdAt { into.createdAt = from.createdAt }
        into.updatedAt = stamp

        // 5. Soft-delete the duplicate.
        from.deletedAt = stamp
        from.updatedAt = stamp

        try context.save()
    }

    /// Repoints every `Link` whose endpoint points at `fromID` onto `intoID`,
    /// deleting any edge that would become a duplicate. Both incoming (`toID`) and
    /// outgoing (`fromID`) directions are handled defensively.
    private func repointEdges(from fromID: UUID, into intoID: UUID) throws {
        let links = LinkRepository(context: context)
        let intoEndpoint: (ItemKind, UUID) = (.task, intoID)
        let fromEndpoint: (ItemKind, UUID) = (.task, fromID)

        var existingIncoming = Set(try links.backlinks(to: intoEndpoint).map { Self.edgeKey($0) })
        for edge in try links.backlinks(to: fromEndpoint) {
            edge.toID = intoID
            let key = Self.edgeKey(edge)
            if existingIncoming.contains(key) {
                context.delete(edge)
            } else {
                existingIncoming.insert(key)
            }
        }

        var existingOutgoing = Set(try links.outgoing(from: intoEndpoint).map { Self.edgeKey($0) })
        for edge in try links.outgoing(from: fromEndpoint) {
            edge.fromID = intoID
            let key = Self.edgeKey(edge)
            if existingOutgoing.contains(key) {
                context.delete(edge)
            } else {
                existingOutgoing.insert(key)
            }
        }
    }

    /// Fills nil / zero-sentinel survivor fields from the loser's values.
    /// Only nilable fields are candidates; non-optional fields are overwritten
    /// only when the survivor holds the zero-value sentinel (empty body, `.none` priority).
    private func fillEmptyFields(into: TaskItem, from: TaskItem) {
        if into.body.isEmpty { into.body = from.body }
        if into.noteRef == nil { into.noteRef = from.noteRef }
        if into.dueAt == nil { into.dueAt = from.dueAt }
        if into.startAt == nil { into.startAt = from.startAt }
        if into.endAt == nil { into.endAt = from.endAt }
        if into.deadlineAt == nil { into.deadlineAt = from.deadlineAt }
        if into.priority == .none { into.priorityRaw = from.priorityRaw }
        if into.projectID == nil { into.projectID = from.projectID }
        if into.sectionID == nil { into.sectionID = from.sectionID }
        if into.recurrenceRule == nil { into.recurrenceRule = from.recurrenceRule }
        if into.externalSourceID == nil { into.externalSourceID = from.externalSourceID }
        if into.estimatedDurationSeconds == nil { into.estimatedDurationSeconds = from.estimatedDurationSeconds }
    }

    /// Identity key for de-duplicating a `Link` by endpoints + edge label.
    /// Mirrors `PersonRepository.edgeKey`.
    private static func edgeKey(_ edge: Link) -> String {
        "\(edge.fromKind.rawValue):\(edge.fromID.uuidString):\(edge.toKind.rawValue):\(edge.toID.uuidString):\(edge.linkKind.rawValue)"
    }
}
