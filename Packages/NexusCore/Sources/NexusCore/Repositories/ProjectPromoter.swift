import Foundation
import SwiftData

/// Promotes a complex task into a first-class `Project` (Projects tier, spec §6.1,
/// decision D5 — "create-first, organize-later"). The original task's identity
/// dissolves into a `Project` + its backing note:
///
/// 1. create a `Project` (`name = task.title`, `status = .planned`);
/// 2. adopt the canonical backing **note**: reuse the task's existing detail note
///    when it has one (so its todos aren't double-`containsTask`-linked and the
///    note isn't orphaned, P2), else create one from the task body; wire
///    `Project.canonicalNoteRef`;
/// 3. re-parent the task's direct children onto the new project (they become the
///    project's phases) and detach their `parentTaskID`;
/// 4. **repoint** the original task's graph edges (`blocks` in/out, `mentions`,
///    `labeled`) onto the `Project` endpoint;
/// 5. cascade the task's dependent rows (comments + scheduled blocks, P3) and
///    soft-delete the original task.
///
/// Atomic per invariant I6: every mutation runs on one `ModelContext` and is
/// committed by a single terminal `context.save()`. If any step throws, nothing
/// is saved, so no orphaned project / note / edge is left behind. `demoteToTask`
/// is out of scope (spec §2).
@MainActor
public struct ProjectPromoter {
    public let context: ModelContext
    public let now: () -> Date
    private let links: LinkRepository

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
        self.links = LinkRepository(context: context)
    }

    /// The kinds of edge that move from the task to the project on promotion.
    /// `.child`/`.containsTask`/`.scheduledAs` are task-structural and handled by
    /// the explicit re-parent / soft-delete steps, so they are NOT blindly
    /// repointed here.
    private static let repointedKinds: Set<LinkKind> = [.blocks, .mentions, .labeled]

    /// Runs the atomic promotion and returns the new `Project`. Throws (saving
    /// nothing) if the task is already deleted.
    @discardableResult
    public func promoteToProject(_ task: TaskItem) throws -> Project {
        guard task.deletedAt == nil else {
            throw ProjectPromotionError.taskAlreadyDeleted(taskID: task.id)
        }
        let stamp = now()

        // 1. Project.
        let project = Project(name: task.title, status: .planned)
        project.createdAt = stamp
        project.updatedAt = stamp
        context.insert(project)

        // 2. Backing note. Prefer the task's existing detail note as the canonical
        //    project page: re-serializing it into a fresh note would mint a SECOND
        //    `containsTask` edge to every todo it already owns and leave the
        //    original note orphaned (P2). Only when the task has no note do we
        //    create one from its body. Either way the note is mutated/inserted
        //    directly (not via NoteRepository) so the whole promotion shares this
        //    method's single terminal save (atomicity, I6).
        let note: Note
        if let existingNote = try TaskNoteContent.note(for: task, in: context) {
            existingNote.title = task.title
            existingNote.role = .projectPage
            existingNote.updatedAt = stamp
            // The dead task must no longer point at what is now the project page.
            task.noteRef = nil
            note = existingNote
        } else {
            let blocks = MarkdownBlockParser.parse(task.body.trimmingCharacters(in: .whitespacesAndNewlines))
            let created = Note(
                title: task.title,
                contentData: try NoteContentCoder.encode(blocks),
                role: .projectPage
            )
            created.createdAt = stamp
            created.updatedAt = stamp
            context.insert(created)
            note = created
        }
        // Wire `canonicalNoteRef` BEFORE reconcile: the reconciler mints a
        // `TaskItem` for every unbound checkbox in the body and routes it via
        // `NoteReconciler.projectContext`, which queries `canonicalNoteRef ==
        // note.id`. Setting the ref first lets those todos resolve to THIS project
        // (its phases); reconciling first would find no owning project and dump
        // every promoted-body todo into Inbox.
        project.canonicalNoteRef = note.id
        // Build the note's blob↔graph mirror + search/plainText cache before the
        // single terminal save (mirrors NoteRepository.create's reconcile step),
        // so the project page is queryable immediately rather than only after the
        // next reconcileOnLoad. The reconciler does not save — atomicity (I6) is
        // preserved by this method's lone `context.save()`.
        _ = try NoteReconciler(context: context).reconcile(note)

        // 3. Re-parent direct children → project phases.
        for child in try directChildren(of: task) {
            child.parentTaskID = nil
            child.projectID = project.id
            child.updatedAt = stamp
        }

        // 4. Repoint the task's graph edges onto the project endpoint.
        try repointEdges(from: task, to: project)

        // 5. Cascade the task's dependent rows, then soft-delete it.
        try cascadeDependents(of: task, stamp: stamp)
        task.deletedAt = stamp
        task.updatedAt = stamp

        try context.save()
        return project
    }

    /// Soft-deletes the rows that hang off the dissolving task: its comments and
    /// scheduled blocks (P3). Without this they stay anchored to a dead task —
    /// invisible but live. Inlined rather than calling the repos' `softDeleteAll`
    /// (which each issue their own `context.save()`) so the cascade lands in this
    /// method's single terminal save (I6).
    ///
    /// NOTE: a mirror EventKit event for an *accepted* block is NOT removed here —
    /// the promoter is pure-core with no calendar writer (same limitation as
    /// `schedule.reject_block`, A3). Cleaning that up is a known follow-up.
    private func cascadeDependents(of task: TaskItem, stamp: Date) throws {
        let taskID = task.id

        // Comments are keyed by (itemID, itemKind) fields, not graph edges; the
        // enum can't be matched in #Predicate, so filter kind in-memory (mirrors
        // CommentRepository.comments(for:kind:)).
        let comments = try context.fetch(
            FetchDescriptor<Comment>(predicate: #Predicate { $0.itemID == taskID && $0.deletedAt == nil })
        )
        .filter { $0.itemKind == .task }
        for comment in comments {
            comment.deletedAt = stamp
        }

        // Scheduled blocks carry their own `.scheduledAs` edge; drop it so the
        // graph no longer points at a dead block (mirrors ScheduledBlockRepository).
        let blocks = try context.fetch(
            FetchDescriptor<ScheduledBlock>(predicate: #Predicate { $0.taskID == taskID && $0.deletedAt == nil })
        )
        for block in blocks {
            block.deletedAt = stamp
            block.updatedAt = stamp
            let blockID = block.id
            let edges = try context.fetch(
                FetchDescriptor<Link>(predicate: #Predicate { $0.toID == blockID })
            )
            .filter { $0.toKind == .scheduledBlock && $0.linkKind == .scheduledAs }
            for edge in edges {
                context.delete(edge)
            }
        }
    }

    private func directChildren(of task: TaskItem) throws -> [TaskItem] {
        let parentID = task.id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { child in
                child.parentTaskID == parentID && child.deletedAt == nil
            }
        )
        return try context.fetch(descriptor)
    }

    /// Moves the task's outgoing and incoming `blocks`/`mentions`/`labeled` edges
    /// to the project endpoint, de-duplicating against any edge that already
    /// exists there, then deletes the original task edge. No edge is left dangling.
    private func repointEdges(from task: TaskItem, to project: Project) throws {
        let taskEndpoint: (ItemKind, UUID) = (.task, task.id)
        let projectEndpoint: (ItemKind, UUID) = (.project, project.id)

        for edge in try links.outgoing(from: taskEndpoint)
        where Self.repointedKinds.contains(edge.linkKind) {
            _ = try links.findOrCreate(
                from: projectEndpoint,
                to: (edge.toKind, edge.toID),
                linkKind: edge.linkKind
            )
            try links.delete(edge)
        }

        for edge in try links.backlinks(to: taskEndpoint)
        where Self.repointedKinds.contains(edge.linkKind) {
            _ = try links.findOrCreate(
                from: (edge.fromKind, edge.fromID),
                to: projectEndpoint,
                linkKind: edge.linkKind
            )
            try links.delete(edge)
        }
    }
}

public enum ProjectPromotionError: Error, Equatable {
    case taskAlreadyDeleted(taskID: UUID)
}
