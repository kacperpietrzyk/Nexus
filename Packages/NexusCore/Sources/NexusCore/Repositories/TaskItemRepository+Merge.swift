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
    /// carries the earlier `createdAt`, re-parents the loser's live subtasks to root,
    /// and soft-deletes the loser. Mirrors `PersonRepository.mergePeople(into:from:)`.
    ///
    /// All mutations run on one `ModelContext` and commit via a single terminal
    /// `context.save()`. Edge repointing mutates `Link` endpoints directly rather
    /// than routing through `LinkRepository` (whose `findOrCreate`/`delete` each
    /// save), so a throw before the terminal save leaves nothing persisted —
    /// no orphaned edge (I2). Throws (saving nothing) if `from` and `into` are
    /// the same task or `from` is already deleted.
    ///
    /// **Subtask re-parenting:** `parentTaskID` (task hierarchy) is a scalar pointer,
    /// not a `Link`. The loser's live direct children are detached to root
    /// (`parentTaskID = nil`) before the loser is soft-deleted, preventing them from
    /// dangling at a tombstone. Mirrors `ProjectPromoter`'s `directChildren` detach.
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

        // 5. Re-parent the loser's live direct children to root so they don't
        //    dangle at a tombstone. Mirrors `ProjectPromoter.promoteToProject`'s
        //    `directChildren` detach step. Runs before the soft-delete so the
        //    predicate (`deletedAt == nil`) still matches them.
        for child in try liveChildren(of: from) {
            child.parentTaskID = nil
            child.updatedAt = stamp
        }

        // 6. Soft-delete the duplicate.
        from.deletedAt = stamp
        from.updatedAt = stamp

        try context.save()
    }

    /// Repoints every `Link` whose endpoint points at `fromID` onto `intoID`,
    /// deleting any edge that would become a duplicate after repointing. Both
    /// incoming (`toID`) and outgoing (`fromID`) directions are handled defensively.
    ///
    /// **Self-loop guard:** if repointing an outgoing edge would produce a
    /// task→task edge where `fromID == toID` (i.e., `from` and `into` were
    /// connected to each other — a dependency/blocks relationship), the edge is
    /// dropped rather than preserved as a self-referential loop.
    private func repointEdges(from fromID: UUID, into intoID: UUID) throws {
        let links = LinkRepository(context: context)
        let intoEndpoint: (ItemKind, UUID) = (.task, intoID)
        let fromEndpoint: (ItemKind, UUID) = (.task, fromID)

        var existingIncoming = Set(try links.backlinks(to: intoEndpoint).map { Self.edgeKey($0) })
        for edge in try links.backlinks(to: fromEndpoint) {
            edge.toID = intoID
            // Drop self-loops (e.g. from blocks into — would produce into→into).
            if edge.fromID == intoID {
                context.delete(edge)
                continue
            }
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
            // Drop self-loops (e.g. into blocks from — would produce into→into).
            if edge.toID == intoID {
                context.delete(edge)
                continue
            }
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
    /// Paired blobs are always carried together:
    /// - `externalSourceID`+`externalSourceMetadata` — re-migration sentinel pair.
    /// - `estimatedDurationSeconds`+`durationSourceRaw` — value+provenance pair;
    ///   the source governs the override cascade (spec §4.2, invariant I-C1).
    ///
    /// **`workflowStateRaw` is intentionally NOT filled.** Setting it without
    /// reconciling `statusRaw` would violate invariant I1 (workflowState ⇒ status);
    /// the only sanctioned path is `setWorkflowState`, which calls `context.save()`
    /// internally and is therefore incompatible with this method's caller's single
    /// terminal `save()` (I2). Deferred as a known follow-up.
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
        if into.cycleID == nil { into.cycleID = from.cycleID }
        if into.assignedAgent == nil { into.assignedAgent = from.assignedAgent }
        if into.recurrenceRule == nil { into.recurrenceRule = from.recurrenceRule }
        if into.externalSourceID == nil {
            // Carry the paired (id, metadata) blob together — a partial carry would
            // leave the re-migration sentinel without its raw-record blob.
            into.externalSourceID = from.externalSourceID
            into.externalSourceMetadata = from.externalSourceMetadata
        }
        if into.estimatedDurationSeconds == nil {
            // Carry the paired (value, provenance) blob together — the source governs
            // the override cascade and must not be separated from its estimate.
            into.estimatedDurationSeconds = from.estimatedDurationSeconds
            into.durationSourceRaw = from.durationSourceRaw
        }
    }

    /// Identity key for de-duplicating a `Link` by endpoints + edge label.
    /// Mirrors `PersonRepository.edgeKey`.
    private static func edgeKey(_ edge: Link) -> String {
        "\(edge.fromKind.rawValue):\(edge.fromID.uuidString):\(edge.toKind.rawValue):\(edge.toID.uuidString):\(edge.linkKind.rawValue)"
    }

    /// Returns the live (non-soft-deleted) direct children of `task`.
    /// Mirrors `ProjectPromoter.directChildren(of:)` and the
    /// `activeSubtasks(parentID:)` predicate in `TaskItemRepository+Subtasks`.
    private func liveChildren(of task: TaskItem) throws -> [TaskItem] {
        let parentID = task.id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { child in
                child.parentTaskID == parentID && child.deletedAt == nil
            }
        )
        return try context.fetch(descriptor)
    }
}
