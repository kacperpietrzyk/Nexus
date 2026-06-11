import NexusCore
import Observation
import SwiftUI

/// Editor state for a single `Note`: the decoded `[Block]` working copy + the
/// title, with persistence routed through `NoteRepository` so every mutation
/// reconciles the mirror (Link/Task) and updates the `plainText` cache in one
/// transaction (spec §6.4).
///
/// The working copy is the source of truth for the editing session; each commit
/// re-encodes through `updateContent`, which the reconciler may further rewrite
/// (e.g. mint a `TaskItem` for a new todo block, bind a pending wikilink). After a
/// structural commit we re-read the persisted blocks so the view reflects any
/// reconciler rewrite.
@MainActor
@Observable
public final class NoteEditorModel {
    public private(set) var blocks: [Block]
    public var title: String
    /// The note's normalized tags (A2). Source of truth for the editor session;
    /// each add/remove persists through `updateFields(tags:)` so the reconciler
    /// and `plainText` cache stay consistent in one transaction.
    public private(set) var tags: [String]
    /// The note's custom property bag (Tranche 2 Plan E). Ordered; keys unique
    /// case-sensitively (`NotePropertyEditing` enforces). Persists through
    /// `NoteRepository.updateProperties` — never writes the blob directly.
    public private(set) var properties: [NoteProperty]
    /// The note's folder placement; nil = root. Persists through
    /// `NoteRepository.setFolderPath`.
    public private(set) var folderPath: String?

    private let note: Note
    private let repository: NoteRepository?

    public init(note: Note, repository: NoteRepository?) {
        self.note = note
        self.repository = repository
        self.title = note.title
        self.tags = NoteListGrouping.normalizedTags(note.tags)
        self.properties = note.properties
        self.folderPath = note.folderPath
        self.blocks = (try? NoteContentCoder.decode(note.contentData)) ?? []
    }

    public var canEdit: Bool { repository != nil }

    // MARK: - Metadata (A3 properties panel)

    public var role: NoteRole { note.role }
    public var createdAt: Date { note.createdAt }
    public var updatedAt: Date { note.updatedAt }

    // MARK: - Tags (A2)

    /// Add a typed tag (the field accepts an optional leading `#`), de-duplicated
    /// and persisted. A blank or duplicate entry is a no-op beyond normalization.
    public func addTag(_ raw: String) {
        let updated = NoteListGrouping.addTag(raw, to: tags)
        guard updated != tags else { return }
        tags = updated
        try? repository?.updateFields(note, tags: tags)
    }

    /// Remove a tag (case-insensitive) and persist.
    public func removeTag(_ tag: String) {
        let updated = NoteListGrouping.removeTag(tag, from: tags)
        guard updated != tags else { return }
        tags = updated
        try? repository?.updateFields(note, tags: tags)
    }

    // MARK: - Properties + folder (Tranche 2 Plan E)

    /// Add a property with an empty text value. No-op for a blank or duplicate key.
    public func addProperty(key: String) {
        guard let updated = NotePropertyEditing.add(key: key, to: properties) else { return }
        properties = updated
        persistProperties()
    }

    /// Rename a property key in place. No-op when the target is blank or collides.
    public func renameProperty(_ key: String, to newKey: String) {
        guard let updated = NotePropertyEditing.rename(key: key, to: newKey, in: properties),
            updated != properties
        else { return }
        properties = updated
        persistProperties()
    }

    public func setPropertyValue(_ value: NotePropertyValue, forKey key: String) {
        guard let updated = NotePropertyEditing.setValue(value, forKey: key, in: properties),
            updated != properties
        else { return }
        properties = updated
        persistProperties()
    }

    public func removeProperty(_ key: String) {
        let updated = NotePropertyEditing.remove(key: key, from: properties)
        guard updated != properties else { return }
        properties = updated
        persistProperties()
    }

    /// Move the note to a folder; the raw path is normalized (nil/blank = root).
    public func setFolderPath(_ raw: String?) {
        let normalized = NoteFolderPath.normalize(raw)
        guard normalized != folderPath else { return }
        folderPath = normalized
        try? repository?.setFolderPath(note, raw)
    }

    private func persistProperties() {
        try? repository?.updateProperties(note, properties: properties)
    }

    // MARK: - Title

    public func commitTitle() {
        guard let repository, title != note.title else { return }
        try? repository.updateFields(note, title: title)
    }

    // MARK: - Block mutations

    /// Replace the working block list and persist. Re-reads the persisted blocks so
    /// any reconciler rewrite (new task minted, wikilink bound) is reflected.
    public func apply(_ newBlocks: [Block]) {
        blocks = newBlocks
        persist()
    }

    public func insert(_ new: BlockListOps.NewBlock, after afterID: UUID?) {
        apply(BlockListOps.insert(BlockListOps.makeBlock(new), after: afterID, in: blocks))
    }

    public func remove(id: UUID) {
        apply(BlockListOps.remove(id: id, in: blocks))
    }

    public func move(from offsets: IndexSet, to destination: Int) {
        apply(BlockListOps.move(in: blocks, from: offsets, to: destination))
    }

    public func convert(blockID: UUID, to new: BlockListOps.NewBlock) {
        apply(BlockListOps.convert(blockID: blockID, to: new, in: blocks))
    }

    /// Set the plain text of a text-bearing block (staged editing — collapses the
    /// block to a single unmarked run, spec §5).
    public func setPlainText(_ text: String, forBlock id: UUID) {
        let runs = InlineRunRendering.runs(fromPlainText: text)
        apply(BlockListOps.setRuns(runs, forBlock: id, in: blocks))
    }

    public func setCode(_ text: String, forBlock id: UUID) {
        apply(BlockListOps.setCode(text, forBlock: id, in: blocks))
    }

    public func setHTML(_ raw: String, forBlock id: UUID) {
        apply(BlockListOps.setHTML(raw, forBlock: id, in: blocks))
    }

    /// Insert a wikilink/embed target chosen from the picker, by id (spec §9 — never
    /// store by title). `asEmbed` adds a standalone embed block; otherwise an inline
    /// link run is appended to a new paragraph (full inline-span insertion is a later
    /// stage; this gets a working ref into the graph now).
    public func insertLink(to candidate: LinkCandidate, asEmbed: Bool, after afterID: UUID?) {
        let block: Block
        if asEmbed {
            block = Block(kind: .embed(ref: candidate.id, kind: candidate.kind))
        } else {
            let run = InlineRun(
                text: candidate.title,
                marks: [.link(ref: candidate.id, href: nil)]
            )
            block = Block(kind: .paragraph(runs: [run]))
        }
        apply(BlockListOps.insert(block, after: afterID, in: blocks))
    }

    // MARK: - Checkbox → Task seam (§7)

    /// Toggle a todo block's completion through the repository so the underlying
    /// `TaskItem` (the single source of truth) drives the change everywhere.
    public func toggleTodo(blockID: UUID) {
        try? repository?.toggleTodo(note, blockID: blockID)
    }

    /// Edit a todo block's label, which writes the `TaskItem.title` too (§7).
    public func editTodoText(_ text: String, blockID: UUID) {
        try? repository?.editTodoText(note, blockID: blockID, text: text)
        reload()
    }

    // MARK: - Live resolution (render-time reads, spec §7/§10)
    //
    // A todo block's live `TaskItem` status/title is observed directly in
    // `TodoBlockView` via `@Query` (the task is the source of truth and must
    // refresh the row on any change), so there is no snapshot accessor here.

    /// A lightweight read-only snapshot of an embedded object for inline preview
    /// (spec §10). nil for cross-module targets (e.g. Meeting) the core resolver
    /// can't reach — those render as an unresolved placeholder.
    public func embedSnapshot(for ref: UUID) -> NoteRepository.EmbedSnapshot? {
        try? repository?.embedSnapshot(for: ref)
    }

    // MARK: - Persistence

    private func persist() {
        guard let repository else { return }
        try? repository.updateContent(note, blocks: blocks)
        reload()
    }

    /// Re-read the persisted blocks after a reconciler-affecting write.
    private func reload() {
        blocks = (try? NoteContentCoder.decode(note.contentData)) ?? blocks
    }
}
