import Foundation
import SwiftData

/// Promotes a complex task into a first-class `Project` (Projects tier, spec §6.1,
/// decision D5 — "create-first, organize-later"). The original task's identity
/// dissolves into a `Project` + its backing note:
///
/// 1. create a `Project` (`name = task.title`, `status = .planned`);
/// 2. create the canonical backing **note** from the task body (Notes content
///    layer) and wire `Project.canonicalNoteRef`;
/// 3. re-parent the task's direct children onto the new project (they become the
///    project's phases) and detach their `parentTaskID`;
/// 4. **repoint** the original task's graph edges (`blocks` in/out, `mentions`,
///    `labeled`) onto the `Project` endpoint;
/// 5. soft-delete the original task.
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

        // 2. Backing note from the task body (title → note title, body markdown →
        //    blocks). Inserted directly (not via NoteRepository) so the whole
        //    promotion shares this method's single terminal save (atomicity, I6).
        let blocks = try MarkdownBlockParser.parse(TaskNoteContent.markdown(for: task, in: context))
        let note = Note(
            title: task.title,
            contentData: try NoteContentCoder.encode(blocks),
            role: .projectPage
        )
        note.createdAt = stamp
        note.updatedAt = stamp
        context.insert(note)
        // Build the note's blob↔graph mirror + search/plainText cache before the
        // single terminal save (mirrors NoteRepository.create's reconcile step),
        // so the project page is queryable immediately rather than only after the
        // next reconcileOnLoad. The reconciler does not save — atomicity (I6) is
        // preserved by this method's lone `context.save()`.
        _ = try NoteReconciler(context: context).reconcile(note)
        project.canonicalNoteRef = note.id

        // 3. Re-parent direct children → project phases.
        for child in try directChildren(of: task) {
            child.parentTaskID = nil
            child.projectID = project.id
            child.updatedAt = stamp
        }

        // 4. Repoint the task's graph edges onto the project endpoint.
        try repointEdges(from: task, to: project)

        // 5. Soft-delete the original task.
        task.deletedAt = stamp
        task.updatedAt = stamp

        try context.save()
        return project
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
