import Foundation
import SwiftData

/// CRUD over `Note`, driving the `NoteReconciler` and owning the single
/// `context.save()` per operation (spec §6.4 save boundary). Also exposes the
/// editor-driven checkbox→Task seam ops (§7) and the embed snapshot resolver
/// (§10). Bound to a single `ModelContext`; never share across actors.
///
/// ## Save boundary
/// Every mutating method follows: mutate the blob/fields → `reconciler.reconcile`
/// (mirror + cache, no save) → exactly one `context.save()`. So a blob change and
/// its entire derived mirror land in one transaction.
///
/// ## Checkbox seam (§7, §10 of advisor guidance)
/// The block runs are a *cached label*; the `TaskItem` is the source of truth.
/// `editTodoText` writes BOTH the task title and the block's cached runs in one
/// op, so reconcile never has to refresh labels (no per-load blob churn).
/// `toggleTodo` drives `complete()`/reopen on the task — the single source of
/// truth — so the change is visible everywhere the task appears.
@MainActor
public final class NoteRepository {
    public let context: ModelContext
    public let reconciler: NoteReconciler
    /// Used to complete/reopen tasks through the real lifecycle (recurrence
    /// side-effects, notifications). Optional: a pure-core caller that only edits
    /// content can omit it; `toggleTodo` then mutates the task status directly.
    private let tasks: TaskItemRepository?
    private let now: () -> Date
    /// Search/Spotlight observers (mirrors `LinkableRepository`). When non-empty, the
    /// repo fires `didUpsert` after any op that changes the note's indexed text
    /// (`plainText`/`title`) and `didSoftDelete` after `delete`. Default empty so
    /// pure-core callers and tests are unaffected.
    private let observers: [any LinkableObserver]

    public init(
        context: ModelContext,
        tasks: TaskItemRepository? = nil,
        now: @escaping () -> Date = Date.init,
        observers: [any LinkableObserver] = []
    ) {
        self.context = context
        self.reconciler = NoteReconciler(context: context)
        self.tasks = tasks
        self.now = now
        self.observers = observers
    }

    /// Fans out an upsert for `note` to every observer. The `Sendable`
    /// `IndexedDocument` snapshot is built here on `@MainActor` (where the row is
    /// safe to read), then awaited into each observer's actor via a detached `Task`
    /// so the repo's `@MainActor` context is never blocked. Mirrors
    /// `LinkableRepository.broadcastUpsert`.
    private func broadcastUpsert(for note: Note) {
        guard !observers.isEmpty else { return }
        let document = IndexedDocument(note)
        for observer in observers {
            _Concurrency.Task { await observer.didUpsert(document) }
        }
    }

    // MARK: - CRUD

    /// Create a `Note` from already-encoded block content, reconcile, and save.
    @discardableResult
    public func create(
        title: String = "",
        blocks: [Block] = [],
        role: NoteRole = .free,
        tags: [String] = []
    ) throws -> Note {
        let note = Note(
            title: title,
            contentData: try NoteContentCoder.encode(blocks),
            role: role,
            tags: tags
        )
        context.insert(note)
        try reconciler.reconcile(note)
        try context.save()
        broadcastUpsert(for: note)
        return note
    }

    public func find(id: UUID) throws -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first { $0.deletedAt == nil }
    }

    /// Overwrite a note's content blocks, reconcile the mirror + cache, save.
    public func updateContent(_ note: Note, blocks: [Block]) throws {
        note.contentData = try NoteContentCoder.encode(blocks)
        note.updatedAt = now()
        try reconciler.reconcile(note)
        try context.save()
        broadcastUpsert(for: note)
    }

    /// Update scalar fields (title/tags/role); content is untouched. Still drives
    /// reconcile so a `role` change (free → projectPage) re-homes new todos.
    public func updateFields(
        _ note: Note,
        title: String? = nil,
        tags: [String]? = nil,
        role: NoteRole? = nil
    ) throws {
        if let title { note.title = title }
        if let tags { note.tags = tags }
        if let role { note.role = role }
        note.updatedAt = now()
        try reconciler.reconcile(note)
        try context.save()
        broadcastUpsert(for: note)
    }

    /// Recompute-on-load (spec §6.2): repair any blob↔graph drift from a crash
    /// between save-blob and write-mirror. Saves + bumps `updatedAt` only if the
    /// reconcile actually changed something, so opening a clean note doesn't churn
    /// CloudKit LWW order or fire a redundant re-index.
    @discardableResult
    public func reconcileOnLoad(_ note: Note) throws -> Bool {
        let changed = try reconciler.reconcile(note)
        if changed {
            note.updatedAt = now()
            try context.save()
            broadcastUpsert(for: note)
        }
        return changed
    }

    /// Delete a note (spec §8): three independent sweeps —
    /// (a) delete outgoing links where `fromID == note.id` (todos detach, tasks
    ///     survive); incoming links are left for their owners to repair;
    /// (b) null `TaskItem.noteRef` pointing at this note (the task's own content);
    /// (c) null `Project.canonicalNoteRef` pointing at this note.
    /// `TaskItem.noteRef` (task content) is distinct from the `containsTask` edge
    /// (note-contains-todo) — both are cleared, by (a) and (b) respectively.
    public func delete(_ note: Note) throws {
        let noteID = note.id

        let outgoing = try context.fetch(
            FetchDescriptor<Link>(predicate: #Predicate { $0.fromID == noteID })
        )
        for link in outgoing {
            context.delete(link)
        }

        for task in try context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.noteRef == noteID })
        ) {
            task.noteRef = nil
            task.updatedAt = now()
        }

        for project in try context.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.canonicalNoteRef == noteID })
        ) {
            project.canonicalNoteRef = nil
            project.updatedAt = now()
        }

        let stamp = now()
        note.deletedAt = stamp
        note.updatedAt = stamp
        try context.save()
        let id = note.id
        for observer in observers {
            _Concurrency.Task { await observer.didSoftDelete(kind: .note, id: id) }
        }
    }

    // MARK: - Checkbox → Task seam (§7)

    /// Editor edits the text of a checkbox: writes BOTH `TaskItem.title` (truth)
    /// and the block's cached runs (label), in one op + one save. Reconcile is not
    /// needed for the label (it's already consistent) but the blob did change, so
    /// we re-encode and refresh `plainText`.
    public func editTodoText(_ note: Note, blockID: UUID, text: String) throws {
        var blocks = try NoteContentCoder.decode(note.contentData)
        guard let index = blocks.firstIndex(where: { $0.id == blockID }),
            case .todo(let taskRef, _) = blocks[index].kind
        else { return }

        let runs = [InlineRun(text: text)]
        blocks[index].kind = .todo(taskRef: taskRef, runs: runs)
        note.contentData = try NoteContentCoder.encode(blocks)
        note.updatedAt = now()

        if let task = try fetchTask(id: taskRef) {
            task.title = text
            task.updatedAt = now()
        }

        try reconciler.reconcile(note)
        try context.save()
        broadcastUpsert(for: note)
    }

    /// Editor toggles a checkbox: complete (when opening→done) or reopen the
    /// underlying `TaskItem` — the single source of truth, so the change shows up
    /// everywhere the task appears. No blob change (status lives on the task).
    public func toggleTodo(_ note: Note, blockID: UUID) throws {
        let blocks = try NoteContentCoder.decode(note.contentData)
        guard let block = blocks.first(where: { $0.id == blockID }),
            case .todo(let taskRef, _) = block.kind,
            let task = try fetchTask(id: taskRef)
        else { return }

        let shouldComplete = task.status != .done
        if let tasks {
            if shouldComplete {
                try tasks.markDone(task)
            } else {
                try tasks.reopen(task)
            }
            return  // TaskItemRepository owns its own save + side-effects.
        }

        // No injected TaskItemRepository: flip status directly (pure-core path).
        task.statusRaw = (shouldComplete ? TaskStatus.done : TaskStatus.open).rawValue
        task.lastCompletedAt = shouldComplete ? now() : nil
        task.updatedAt = now()
        try context.save()
    }

    // MARK: - Embed snapshot (§10)

    /// A lightweight, read-only snapshot of an embedded object for inline preview
    /// (spec §10). NexusCore returns title + minimal meta; the rich render lives in
    /// `NotesFeature`. Cross-module targets (e.g. `Meeting`) are not resolvable
    /// here — callers with broader schema context provide those.
    public struct EmbedSnapshot: Sendable, Equatable {
        public var id: UUID
        public var kind: ItemKind
        public var title: String
        /// e.g. a task's status; nil for objects without a status facet.
        public var status: String?

        public init(id: UUID, kind: ItemKind, title: String, status: String? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.status = status
        }
    }

    public func embedSnapshot(for ref: UUID) throws -> EmbedSnapshot? {
        if let note = try find(id: ref) {
            return EmbedSnapshot(id: note.id, kind: .note, title: note.title)
        }
        if let task = try fetchTask(id: ref) {
            return EmbedSnapshot(id: task.id, kind: .task, title: task.title, status: task.status.rawValue)
        }
        if let project = try firstLive(Project.self, id: ref) {
            return EmbedSnapshot(id: project.id, kind: .project, title: project.name)
        }
        if let section = try firstLive(Section.self, id: ref) {
            return EmbedSnapshot(id: section.id, kind: .section, title: section.name)
        }
        return nil
    }

    // MARK: - Backlinks (§9)

    /// Backlinks to any object = reverse-query the Link graph (spec §9). Thin
    /// pass-through to `LinkRepository.backlinks`; surfaced here so the Notes
    /// surface has a single entry point.
    public func backlinks(to endpoint: (ItemKind, UUID)) throws -> [Link] {
        let id = endpoint.1
        let kind = endpoint.0
        return
            try context
            .fetch(
                FetchDescriptor<Link>(
                    predicate: #Predicate { $0.toID == id },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
            )
            .filter { $0.toKind == kind }
    }

    // MARK: - Lookups

    private func fetchTask(id: UUID) throws -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func firstLive<Model: PersistentModel & Linkable>(
        _ type: Model.Type,
        id: UUID
    ) throws -> Model? {
        try context.fetch(FetchDescriptor<Model>()).first { $0.id == id && $0.deletedAt == nil }
    }
}
