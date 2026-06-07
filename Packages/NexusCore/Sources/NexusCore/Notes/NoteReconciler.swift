import Foundation
import SwiftData

/// Derives the graph mirror (`Link` rows + `TaskItem`s) and the `plainText` cache
/// from a `Note`'s canonical `contentData` blob, keeping them consistent with the
/// blob (spec §6 invariants). It is the single isolator that lets the checkbox→Task
/// seam live in NexusCore so `NotesFeature` never imports `TasksFeature`.
///
/// ## Save boundary (spec §6.4 linchpin)
/// `reconcile(_:)` **mutates the `ModelContext`** (`insert`/`delete` of `Link`/
/// `TaskItem`, sets `note.contentData`/`plainText`/`updatedAt`) but **never calls
/// `context.save()`**. The owning `NoteRepository` performs exactly one save per
/// operation, *after* reconcile, so the blob change and its entire mirror land in
/// one transaction. A crash before that save loses the whole operation atomically —
/// never a silent blob↔graph drift.
///
/// ## Idempotency + recompute-on-load (spec §6.2, §17)
/// `reconcile(_:)` is the *same* function for both "after a blob write" and
/// "on load to repair drift". Running it twice produces the same graph: the
/// `containsTask` link is the durable memory that distinguishes a *new* todo
/// (no link yet → create the task) from a *deleted* task (link exists but the
/// `TaskItem` is gone → §8: convert the block to inert text, drop the stale link).
/// It returns whether anything changed so a clean note doesn't churn `updatedAt`
/// (which would corrupt CloudKit LWW order) or fire a redundant re-index.
///
/// ## Blob rewrites
/// Three paths rewrite `contentData` in place (always before `plainText` is
/// flattened, so the cache reflects the post-rewrite blocks):
/// 1. deleted-task todo → inert paragraph (preserves the text, loses the binding).
/// 2. pending-by-name wikilink → bound `link(ref:)` once the target appears (§9).
/// 3. embed `kind` correction from the parser default (§10).
///
/// ## Scope
/// The reconciler owns only the edge kinds it derives — `containsTask`, `embed`,
/// `mentions` — scoped to `fromID == note.id`. It never touches other edges, and
/// never deletes *incoming* links (their owners recreate them on their own
/// recompute). Cross-module `ItemKind`s (e.g. `meeting`, which is not a NexusCore
/// `@Model`) cannot be probed here; an embed's parser-defaulted kind is corrected
/// only when the target resolves to a NexusCore-resident type.
@MainActor
public struct NoteReconciler {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Recompute the mirror + cache for `note` from its current `contentData`.
    /// Mutates the context; does NOT save. Returns `true` iff anything changed
    /// (blob, plainText, links, or tasks), so the caller can skip the save +
    /// `updatedAt` bump on a clean note.
    @discardableResult
    public func reconcile(_ note: Note) throws -> Bool {
        var blocks = (try? NoteContentCoder.decode(note.contentData)) ?? []
        var blobChanged = false

        // 1. Per-block blob rewrites (todo lifecycle, wikilink binding, embed kind).
        blobChanged = try rewriteBlocks(&blocks, note: note) || blobChanged

        if blobChanged {
            note.contentData = try NoteContentCoder.encode(blocks)
        }

        // 2. plainText cache from the post-rewrite blocks.
        let flattened = NotePlainTextFlattener.plainText(for: blocks)
        let plainTextChanged = note.plainText != flattened
        if plainTextChanged {
            note.plainText = flattened
        }

        // 3. Reconcile the derived Link rows (containsTask / embed / mentions).
        let linksChanged = try reconcileLinks(note: note, blocks: blocks)

        return blobChanged || plainTextChanged || linksChanged
    }

    // MARK: - Block rewrites

    /// Apply the three in-place blob rewrites. Returns whether `blocks` changed.
    private func rewriteBlocks(_ blocks: inout [Block], note: Note) throws -> Bool {
        var changed = false
        for index in blocks.indices {
            switch blocks[index].kind {
            case .todo(let taskRef, let runs):
                if let replacement = try reconcileTodo(taskRef: taskRef, runs: runs, note: note) {
                    blocks[index].kind = replacement
                    changed = true
                }
            case .embed(let ref, let kind):
                // Correct the parser-defaulted kind to the target's real kind when
                // it resolves to a NexusCore type (§10). Leave as-is otherwise
                // (target absent, or a cross-module kind we can't probe here).
                if let corrected = resolveKind(ref), corrected != kind {
                    blocks[index].kind = .embed(ref: ref, kind: corrected)
                    changed = true
                }
            case .paragraph(let runs),
                .heading(_, let runs),
                .bulleted(let runs),
                .numbered(let runs),
                .quote(let runs):
                if let bound = bindWikilinks(in: runs) {
                    blocks[index].kind = replaceRuns(in: blocks[index].kind, with: bound)
                    changed = true
                }
            default:
                break
            }
        }
        return changed
    }

    /// §7/§8 todo lifecycle. Returns a replacement `BlockKind` when the block must
    /// be rewritten (deleted-task → inert paragraph), else `nil` (the live/new-todo
    /// path leaves the block shape unchanged — the `TaskItem` and link are created
    /// with `id == taskRef` so the blob does not need rewriting).
    private func reconcileTodo(taskRef: UUID, runs: [InlineRun], note: Note) throws -> BlockKind? {
        if try fetchTask(id: taskRef) != nil {
            // Live task — nothing to rewrite. Link is (re)created in reconcileLinks.
            return nil
        }
        // No live task. Distinguish a brand-new todo from a deleted-task todo by
        // whether the `containsTask` memory edge already exists.
        if try existingContainsTaskLink(note: note, taskRef: taskRef) != nil {
            // §8 deleted-task: convert to inert paragraph, preserving the runs.
            // (Must NOT remain a todo, or the next pass recreates the task.)
            return .paragraph(runs: runs)
        }
        // Brand-new todo (no task, no memory edge): create the TaskItem with
        // `id == taskRef` so the blob keeps its placeholder ref (no rewrite).
        let task = TaskItem(
            id: taskRef,
            title: Self.label(from: runs),
            projectID: try projectContext(for: note)
        )
        context.insert(task)
        return nil
    }

    /// The project a new todo's `TaskItem` lands in (§8): a `projectPage` note →
    /// the owning `Project`; otherwise → Inbox (`nil`).
    private func projectContext(for note: Note) throws -> UUID? {
        guard note.role == .projectPage else { return nil }
        let noteID = note.id
        var descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.canonicalNoteRef == noteID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.id
    }

    /// Bind pending-by-name wikilinks (`link(ref: nil, href: nil)`, run text ==
    /// title) once a NexusCore-resident target with that title appears (§9). Once
    /// `ref != nil` a wikilink is never re-resolved. Returns rewritten runs, or
    /// `nil` if nothing bound.
    private func bindWikilinks(in runs: [InlineRun]) -> [InlineRun]? {
        var changed = false
        let rewritten = runs.map { run -> InlineRun in
            var marks = run.marks
            var didBind = false
            for markIndex in marks.indices {
                guard case .link(let ref, let href) = marks[markIndex] else { continue }
                guard ref == nil, href == nil else { continue }  // pending-by-name only
                if let resolved = resolveByTitle(run.text) {
                    marks[markIndex] = .link(ref: resolved.id, href: nil)
                    didBind = true
                }
            }
            if didBind {
                changed = true
                return InlineRun(text: run.text, marks: marks)
            }
            return run
        }
        return changed ? rewritten : nil
    }

    // MARK: - Link reconciliation

    /// Recompute the derived edges (`containsTask` for todos, `embed` for embeds,
    /// `mentions` for bound wikilinks) so they exactly match the blob: create
    /// missing, delete stale. Scoped to `fromID == note.id` and the three owned
    /// kinds. Returns whether any link row changed.
    private func reconcileLinks(note: Note, blocks: [Block]) throws -> Bool {
        let required = requiredEdges(note: note, blocks: blocks)
        let owned: Set<LinkKind> = [.containsTask, .embed, .mentions]
        let noteID = note.id
        let existing =
            try context
            .fetch(FetchDescriptor<Link>(predicate: #Predicate { $0.fromID == noteID }))
            .filter { owned.contains($0.linkKind) }

        var changed = false
        var present = Set<Edge>()

        // Delete stale owned edges.
        for link in existing {
            let edge = Edge(toID: link.toID, toKind: link.toKind, kind: link.linkKind)
            if required.contains(edge), !present.contains(edge) {
                present.insert(edge)
            } else {
                context.delete(link)
                changed = true
            }
        }

        // Create missing required edges.
        for edge in required where !present.contains(edge) {
            context.insert(
                Link(
                    from: (.note, note.id),
                    to: (edge.toKind, edge.toID),
                    linkKind: edge.kind
                )
            )
            changed = true
        }

        return changed
    }

    /// The exact set of edges the blob requires. A `Set` keyed by
    /// `(toID, toKind, kind)` so duplicate todos/embeds/wikilinks to one target
    /// collapse to a single link.
    private func requiredEdges(note: Note, blocks: [Block]) -> Set<Edge> {
        var edges = Set<Edge>()
        for block in blocks {
            switch block.kind {
            case .todo(let taskRef, _):
                // Only mirror a todo whose task is (now) live. A deleted-task todo
                // was already converted to inert text in `rewriteBlocks`, so a
                // lingering `.todo` here means a live task.
                edges.insert(Edge(toID: taskRef, toKind: .task, kind: .containsTask))
            case .embed(let ref, let kind):
                edges.insert(Edge(toID: ref, toKind: kind, kind: .embed))
            case .paragraph(let runs),
                .heading(_, let runs),
                .bulleted(let runs),
                .numbered(let runs),
                .quote(let runs):
                for run in runs {
                    for mark in run.marks {
                        if case .link(let ref?, _) = mark {
                            edges.insert(Edge(toID: ref, toKind: resolveKind(ref) ?? .note, kind: .mentions))
                        }
                    }
                }
            default:
                break
            }
        }
        return edges
    }

    private struct Edge: Hashable {
        var toID: UUID
        var toKind: ItemKind
        var kind: LinkKind
    }

    // MARK: - Lookups

    private func fetchTask(id: UUID) throws -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func existingContainsTaskLink(note: Note, taskRef: UUID) throws -> Link? {
        let noteID = note.id
        return
            try context
            .fetch(FetchDescriptor<Link>(predicate: #Predicate { $0.fromID == noteID && $0.toID == taskRef }))
            .first { $0.linkKind == .containsTask }
    }

    /// Probe the NexusCore-resident `Linkable` types for `id`, returning its stored
    /// `kind`. Cross-module types (e.g. `Meeting`) are not registered here and
    /// cannot be resolved — callers with broader schema context correct those.
    /// Filter in Swift (not via a `\Model.id` `#Predicate`) to dodge the generic
    /// keypath-translation trap `LinkableRepository` documents.
    private func resolveKind(_ id: UUID) -> ItemKind? {
        if firstLinkable(Note.self, where: { $0.id == id }) != nil { return .note }
        if firstLinkable(TaskItem.self, where: { $0.id == id }) != nil { return .task }
        if firstLinkable(Project.self, where: { $0.id == id }) != nil { return .project }
        if firstLinkable(Section.self, where: { $0.id == id }) != nil { return .section }
        return nil
    }

    private func resolveByTitle(_ title: String) -> (id: UUID, kind: ItemKind)? {
        // Probe NexusCore Linkables in a fixed order. Single-user scale → an
        // in-memory title scan is acceptable (no universal title index — YAGNI).
        if let note = firstLinkable(Note.self, where: { $0.deletedAt == nil && $0.title == title }) {
            return (note.id, .note)
        }
        if let task = firstLinkable(TaskItem.self, where: { $0.deletedAt == nil && $0.title == title }) {
            return (task.id, .task)
        }
        if let project = firstLinkable(Project.self, where: { $0.deletedAt == nil && $0.title == title }) {
            return (project.id, .project)
        }
        if let section = firstLinkable(Section.self, where: { $0.deletedAt == nil && $0.title == title }) {
            return (section.id, .section)
        }
        return nil
    }

    private func firstLinkable<Model: PersistentModel & Linkable>(
        _ type: Model.Type,
        where matches: (Model) -> Bool
    ) -> Model? {
        try? context.fetch(FetchDescriptor<Model>()).first(where: matches)
    }

    // MARK: - Helpers

    static func label(from runs: [InlineRun]) -> String {
        runs.map(\.text).joined()
    }

    private func replaceRuns(in kind: BlockKind, with runs: [InlineRun]) -> BlockKind {
        switch kind {
        case .paragraph: return .paragraph(runs: runs)
        case .heading(let level, _): return .heading(level: level, runs: runs)
        case .bulleted: return .bulleted(runs: runs)
        case .numbered: return .numbered(runs: runs)
        case .quote: return .quote(runs: runs)
        case .todo(let taskRef, _): return .todo(taskRef: taskRef, runs: runs)
        default: return kind
        }
    }
}
