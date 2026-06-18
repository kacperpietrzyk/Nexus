import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
struct NoteRepositoryTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Note.self, TaskItem.self, Link.self, Project.self, Section.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeContextWithAttachments() throws -> ModelContext {
        let schema = Schema([Note.self, TaskItem.self, Link.self, Project.self, Section.self, AttachmentAsset.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeRepo(_ context: ModelContext) -> NoteRepository {
        NoteRepository(context: context)
    }

    private func outgoing(_ context: ModelContext, from noteID: UUID) throws -> [Link] {
        try context.fetch(FetchDescriptor<Link>()).filter { $0.fromID == noteID }
    }

    // MARK: - CRUD + reconcile drive

    @Test func createReconcilesAndSaves() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let placeholder = UUID()

        let note = try repo.create(
            title: "Doc",
            blocks: [Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "First")]))]
        )

        // Task created, link mirrored, plainText cached — all in the create call.
        #expect(note.plainText == "First")
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).contains { $0.id == placeholder })
        #expect(try outgoing(context, from: note.id).contains { $0.linkKind == .containsTask })
    }

    @Test func updateContentReconcilesNewGraph() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let note = try repo.create(blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "old")]))])

        let target = try repo.create(title: "Target", blocks: [])
        try repo.updateContent(
            note,
            blocks: [
                Block(kind: .paragraph(runs: [InlineRun(text: "Target", marks: [.link(ref: target.id, href: nil)])]))
            ])

        #expect(note.plainText == "Target")
        #expect(try outgoing(context, from: note.id).contains { $0.linkKind == .mentions && $0.toID == target.id })
    }

    @Test func insertImageAttachmentPersistsBlockAndAsset() throws {
        let context = try makeContextWithAttachments()
        let note = Note(contentData: try NoteContentCoder.encode([]))
        context.insert(note)
        try context.save()
        let repo = NoteRepository(context: context)
        let imported = ImportedAttachmentFile(
            id: UUID(),
            originalFilename: "diagram.png",
            mimeType: "image/png",
            byteCount: 4,
            sha256: "hash",
            storagePath: "attachments/id/diagram.png",
            fileURL: URL(fileURLWithPath: "/tmp/diagram.png")
        )

        let asset = try repo.insertImageAttachment(imported, into: note, after: nil)

        #expect(asset.id == imported.id)
        let blocks = try NoteContentCoder.decode(note.contentData)
        guard case .image(let ref, let assetPath) = blocks.first?.kind else {
            Issue.record("expected image block")
            return
        }
        #expect(ref == imported.id)
        #expect(assetPath == imported.storagePath)
        #expect(try context.fetch(FetchDescriptor<AttachmentAsset>()).count == 1)
    }

    // MARK: - reconcileOnLoad gating (no churn on clean note)

    @Test func reconcileOnLoadDoesNotBumpCleanNote() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let note = try repo.create(blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "x")]))])
        let before = note.updatedAt

        let changed = try repo.reconcileOnLoad(note)

        #expect(changed == false)
        #expect(note.updatedAt == before)
    }

    @Test func reconcileOnLoadRepairsAndBumpsDrift() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let note = try repo.create(blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "x")]))])
        note.plainText = "drift"
        let before = note.updatedAt

        let changed = try repo.reconcileOnLoad(note)

        #expect(changed)
        #expect(note.plainText == "x")
        #expect(note.updatedAt >= before)
    }

    // MARK: - Checkbox seam: edit + toggle (§7)

    @Test func editTodoTextUpdatesTaskAndLabel() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let placeholder = UUID()
        let note = try repo.create(blocks: [
            Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "Before")]))
        ])
        let blockID = (try NoteContentCoder.decode(note.contentData))[0].id

        try repo.editTodoText(note, blockID: blockID, text: "After")

        // Task title (truth) updated.
        let task = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == placeholder }
        #expect(task?.title == "After")
        // Cached label + plainText updated.
        guard case .todo(_, let runs) = (try NoteContentCoder.decode(note.contentData))[0].kind else {
            Issue.record("not todo"); return
        }
        #expect(runs.first?.text == "After")
        #expect(note.plainText == "After")
    }

    @Test func toggleTodoCompletesAndReopensTask() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let placeholder = UUID()
        let note = try repo.create(blocks: [
            Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "T")]))
        ])
        let blockID = (try NoteContentCoder.decode(note.contentData))[0].id

        try repo.toggleTodo(note, blockID: blockID)
        var task = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == placeholder }
        #expect(task?.status == .done)

        try repo.toggleTodo(note, blockID: blockID)
        task = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == placeholder }
        #expect(task?.status == .open)
    }

    @Test func toggleTodoViaTaskRepositoryDrivesLifecycle() throws {
        let context = try makeContext()
        let taskRepo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: Date.init)
        let repo = NoteRepository(context: context, tasks: taskRepo)
        let placeholder = UUID()
        let note = try repo.create(blocks: [
            Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "T")]))
        ])
        let blockID = (try NoteContentCoder.decode(note.contentData))[0].id

        try repo.toggleTodo(note, blockID: blockID)

        let task = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == placeholder }
        #expect(task?.status == .done)
        #expect(task?.lastCompletedAt != nil)
    }

    // MARK: - Note deletion sweeps (§8)

    @Test func deleteDetachesTodosClearsRefsKeepsTasks() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let placeholder = UUID()
        let note = try repo.create(blocks: [
            Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "Survivor")]))
        ])
        // A task whose own content lives in this note, and a project page-pointer.
        let task = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == placeholder }
        task?.noteRef = note.id
        let project = Project(name: "P")
        project.canonicalNoteRef = note.id
        context.insert(project)
        try context.save()

        try repo.delete(note)

        // Note tombstoned, its outgoing links gone.
        #expect(note.deletedAt != nil)
        #expect(try outgoing(context, from: note.id).isEmpty)
        // Task survives, but its noteRef is nulled.
        let survivor = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == placeholder }
        #expect(survivor != nil)
        #expect(survivor?.noteRef == nil)
        // Project page pointer nulled.
        #expect(project.canonicalNoteRef == nil)
    }

    // MARK: - Trash / restore (§8)

    @Test func fetchDeletedReturnsOnlyTombstonesNewestFirst() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let live = try repo.create(title: "Live", blocks: [])
        let first = try repo.create(title: "First deleted", blocks: [])
        let second = try repo.create(title: "Second deleted", blocks: [])

        // Delete `first`, then `second`, with distinct timestamps.
        first.deletedAt = Date(timeIntervalSince1970: 1_000)
        second.deletedAt = Date(timeIntervalSince1970: 2_000)
        try context.save()

        let deleted = try repo.fetchDeleted()

        #expect(deleted.map(\.id) == [second.id, first.id])  // newest-deleted first
        #expect(!deleted.contains { $0.id == live.id })
    }

    @Test func restoreClearsTombstoneAndRemirrorsContent() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let placeholder = UUID()
        let note = try repo.create(blocks: [
            Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "Recover me")]))
        ])
        try repo.delete(note)
        #expect(note.deletedAt != nil)
        #expect(try outgoing(context, from: note.id).isEmpty)  // edges detached on delete

        try repo.restore(note)

        // Tombstone cleared and the note is live again.
        #expect(note.deletedAt == nil)
        #expect(try repo.find(id: note.id)?.id == note.id)
        #expect(!(try repo.fetchDeleted().contains { $0.id == note.id }))
        // Reconcile on restore re-mirrors the note's own containsTask edge.
        #expect(try outgoing(context, from: note.id).contains { $0.linkKind == .containsTask })
    }

    // MARK: - Embed snapshot (§10)

    @Test func embedSnapshotResolvesEachKind() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let targetNote = try repo.create(title: "Note T", blocks: [])
        let task = TaskItem(title: "Task T")
        context.insert(task)
        let project = Project(name: "Proj T")
        context.insert(project)
        try context.save()

        #expect(
            try repo.embedSnapshot(for: targetNote.id)
                == NoteRepository.EmbedSnapshot(id: targetNote.id, kind: .note, title: "Note T"))
        #expect(
            try repo.embedSnapshot(for: task.id)
                == NoteRepository.EmbedSnapshot(id: task.id, kind: .task, title: "Task T", status: task.status.rawValue))
        #expect(
            try repo.embedSnapshot(for: project.id)
                == NoteRepository.EmbedSnapshot(id: project.id, kind: .project, title: "Proj T"))
        #expect(try repo.embedSnapshot(for: UUID()) == nil)
    }

    // MARK: - Backlinks (§9)

    @Test func backlinksReverseQueryTheGraph() throws {
        let context = try makeContext()
        let repo = makeRepo(context)
        let target = try repo.create(title: "Hub", blocks: [])
        // Two notes mention the hub.
        _ = try repo.create(blocks: [
            Block(kind: .paragraph(runs: [InlineRun(text: "Hub", marks: [.link(ref: target.id, href: nil)])]))
        ])
        _ = try repo.create(blocks: [
            Block(kind: .paragraph(runs: [InlineRun(text: "Hub", marks: [.link(ref: target.id, href: nil)])]))
        ])

        let backlinks = try repo.backlinks(to: (.note, target.id))
        #expect(backlinks.count == 2)
        #expect(backlinks.allSatisfy { $0.toID == target.id && $0.linkKind == .mentions })
    }

    // MARK: - setPinned

    @Test func setPinnedSetsFlagAndTimestamp() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = NoteRepository(context: context, now: { fixedNow })
        let note = try repo.create(title: "Pinnable")

        try repo.setPinned(note, true)
        #expect(note.isPinned == true)
        #expect(note.pinnedAt == fixedNow)
        #expect(note.updatedAt == fixedNow)

        try repo.setPinned(note, false)
        #expect(note.isPinned == false)
        #expect(note.pinnedAt == nil)
    }
}
