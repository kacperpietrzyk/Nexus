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
/// Errors thrown by the note-template operations on `NoteRepository`.
public enum NoteTemplateError: Error, Equatable {
    /// `instantiateTemplate` was called with a note whose `role != .template`.
    case notATemplate(noteID: UUID)
}

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

    /// Persist imported attachment metadata and insert a note image block in one save boundary.
    @discardableResult
    public func insertImageAttachment(
        _ imported: ImportedAttachmentFile,
        into note: Note,
        after afterID: UUID?
    ) throws -> AttachmentAsset {
        var blocks = try NoteContentCoder.decode(note.contentData)
        let stamp = now()
        let asset = AttachmentAsset(
            id: imported.id,
            originalFilename: imported.originalFilename,
            mimeType: imported.mimeType,
            byteCount: imported.byteCount,
            sha256: imported.sha256,
            storagePath: imported.storagePath,
            createdAt: stamp,
            updatedAt: stamp
        )
        context.insert(asset)

        let block = Block(kind: .image(ref: asset.id, asset: asset.storagePath))
        blocks = Self.inserting(block, after: afterID, in: blocks)
        note.contentData = try NoteContentCoder.encode(blocks)
        note.updatedAt = stamp

        try reconciler.reconcile(note)
        try context.save()
        broadcastUpsert(for: note)
        return asset
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

    // MARK: - Organization (Tranche 2 Plan E: properties + folders)

    /// Replace the note's custom property bag (spec §4.4). The single write path
    /// for `Note.propertiesJSON` — views and agent tools never write the blob.
    /// Keys are unique case-sensitively: the editor enforces uniqueness up front;
    /// defensively, duplicates collapse last-value-wins at the first occurrence's
    /// position so caller order stays deterministic. No reconcile / no index
    /// broadcast: properties are not part of `searchableText` v1 (spec §6.2).
    public func updateProperties(_ note: Note, properties: [NoteProperty]) throws {
        var order: [String] = []
        var valuesByKey: [String: NotePropertyValue] = [:]
        for property in properties {
            if valuesByKey[property.key] == nil { order.append(property.key) }
            valuesByKey[property.key] = property.value
        }
        note.properties = order.compactMap { key in
            valuesByKey[key].map { NoteProperty(key: key, value: $0) }
        }
        note.updatedAt = now()
        try context.save()
    }

    /// Move a note to a folder (spec §4.5). `rawPath` is normalized through
    /// `NoteFolderPath.normalize`; nil / empty / all-junk input means root.
    /// A no-op (no save, no `updatedAt` churn) when the normalized path is
    /// unchanged. No reconcile / no index broadcast — folder placement is not
    /// indexed v1.
    public func setFolderPath(_ note: Note, _ rawPath: String?) throws {
        let normalized = NoteFolderPath.normalize(rawPath)
        guard normalized != note.folderPath else { return }
        note.folderPath = normalized
        note.updatedAt = now()
        try context.save()
    }

    /// Rename/move a derived folder (spec §4.5): one prefix rewrite over every
    /// live note whose `folderPath == old || hasPrefix(old + "/")`, ONE save.
    /// Returns the number of notes rewritten. A target that normalizes to nil
    /// (empty/junk) is rejected as a no-op — use `removeFolder` to dissolve a
    /// folder to root. Tombstoned notes are left untouched.
    @discardableResult
    public func renameFolder(from oldRaw: String, to newRaw: String) throws -> Int {
        guard
            let old = NoteFolderPath.normalize(oldRaw),
            let new = NoteFolderPath.normalize(newRaw),
            old != new
        else { return 0 }
        let prefix = old + "/"
        let stamp = now()
        var moved = 0
        let live = try context.fetch(
            FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt == nil })
        )
        for note in live {
            guard let path = note.folderPath else { continue }
            if path == old {
                note.folderPath = new
            } else if path.hasPrefix(prefix) {
                note.folderPath = new + "/" + String(path.dropFirst(prefix.count))
            } else {
                continue
            }
            note.updatedAt = stamp
            moved += 1
        }
        if moved > 0 { try context.save() }
        return moved
    }

    /// Remove a derived folder, KEEPING its notes (spec §4.5 "remove folder
    /// (keep notes)"): every live note at the path or under it moves to root
    /// (`folderPath = nil`), ONE save. Never deletes a note. Returns the number
    /// of notes moved.
    @discardableResult
    public func removeFolder(_ rawPath: String) throws -> Int {
        guard let target = NoteFolderPath.normalize(rawPath) else { return 0 }
        let prefix = target + "/"
        let stamp = now()
        var moved = 0
        let live = try context.fetch(
            FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt == nil })
        )
        for note in live {
            guard let path = note.folderPath, path == target || path.hasPrefix(prefix) else { continue }
            note.folderPath = nil
            note.updatedAt = stamp
            moved += 1
        }
        if moved > 0 { try context.save() }
        return moved
    }

    /// Instantiate a note template (Tranche 2 Plan D, Obsidian O3 — spec §4.3):
    /// copy `contentData`/`plainText`/`tags`/`propertiesJSON` into a fresh
    /// `.free` note; `folderPath` is copied verbatim; fresh id/timestamps.
    ///
    /// The copy is inserted WITHOUT reconcile, following the
    /// `duplicatedNoteRef` (T1) precedent: the template's derived graph edges
    /// (e.g. `containsTask` for embedded todos) are NOT mirrored onto the
    /// copy, so instantiation can never cross-link the template's tasks.
    /// `plainText` is copied verbatim, so list/search stay consistent without
    /// a reconcile pass.
    @discardableResult
    public func instantiateTemplate(_ template: Note) throws -> Note {
        guard template.role == .template else {
            throw NoteTemplateError.notATemplate(noteID: template.id)
        }
        let copy = Note(
            title: template.title,
            contentData: template.contentData,
            plainText: template.plainText,
            role: .free,
            tags: template.tags
        )
        copy.propertiesJSON = template.propertiesJSON
        copy.folderPath = template.folderPath
        context.insert(copy)
        try context.save()
        broadcastUpsert(for: copy)
        return copy
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

    private static func inserting(_ block: Block, after afterID: UUID?, in blocks: [Block]) -> [Block] {
        guard let afterID, let index = blocks.firstIndex(where: { $0.id == afterID }) else {
            return blocks + [block]
        }

        var updated = blocks
        updated.insert(block, at: index + 1)
        return updated
    }
}
