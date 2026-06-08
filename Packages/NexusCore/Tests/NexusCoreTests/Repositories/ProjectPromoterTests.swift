import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Promotion task → Project (spec §6.1, invariant I6). Verifies the five atomic
/// steps and that graph edges are repointed rather than orphaned.
@Suite("ProjectPromoter")
struct ProjectPromoterTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Label.self, Link.self, TaskItem.self, Project.self, Note.self,
            Comment.self, ScheduledBlock.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    private func insertTask(_ context: ModelContext, title: String, body: String = "") -> TaskItem {
        let task = TaskItem(title: title)
        task.body = body
        context.insert(task)
        return task
    }

    @MainActor
    @Test("promotion creates a planned project with a backing note")
    func createsProjectAndNote() throws {
        let context = try makeContext()
        let task = insertTask(context, title: "ThreatForge", body: "# Goal\n\nShip it.")
        try context.save()

        let promoter = ProjectPromoter(context: context)
        let project = try promoter.promoteToProject(task)

        #expect(project.name == "ThreatForge")
        #expect(project.status == .planned)
        #expect(project.canonicalNoteRef != nil)

        let noteRef = try #require(project.canonicalNoteRef)
        let note = try NoteRepository(context: context).find(id: noteRef)
        #expect(note?.role == .projectPage)
        #expect(note?.title == "ThreatForge")
    }

    @MainActor
    @Test("children re-parent onto the project as phases")
    func childrenReparent() throws {
        let context = try makeContext()
        let parent = insertTask(context, title: "Parent")
        let child = insertTask(context, title: "Phase 1")
        child.parentTaskID = parent.id
        try context.save()

        let project = try ProjectPromoter(context: context).promoteToProject(parent)

        #expect(child.parentTaskID == nil)
        #expect(child.projectID == project.id)
    }

    @MainActor
    @Test("the original task is soft-deleted")
    func originalSoftDeleted() throws {
        let context = try makeContext()
        let task = insertTask(context, title: "Promote me")
        try context.save()

        _ = try ProjectPromoter(context: context).promoteToProject(task)

        #expect(task.deletedAt != nil)
    }

    @MainActor
    @Test("outgoing blocks edge is repointed from task to project")
    func repointsOutgoingBlocks() throws {
        let context = try makeContext()
        let task = insertTask(context, title: "Blocker")
        let blocked = insertTask(context, title: "Blocked")
        try context.save()

        let links = LinkRepository(context: context)
        _ = try links.findOrCreate(from: (.task, task.id), to: (.task, blocked.id), linkKind: .blocks)

        let project = try ProjectPromoter(context: context).promoteToProject(task)

        let fromTask = try links.outgoingBlocks(from: (.task, task.id))
        let fromProject = try links.outgoingBlocks(from: (.project, project.id))
        #expect(fromTask.isEmpty)
        #expect(fromProject.contains { $0.toID == blocked.id })
    }

    @MainActor
    @Test("incoming blocks edge (blocked-by) is repointed to the project")
    func repointsIncomingBlocks() throws {
        let context = try makeContext()
        let blocker = insertTask(context, title: "Blocker")
        let task = insertTask(context, title: "Promote me")
        try context.save()

        let links = LinkRepository(context: context)
        _ = try links.findOrCreate(from: (.task, blocker.id), to: (.task, task.id), linkKind: .blocks)

        let project = try ProjectPromoter(context: context).promoteToProject(task)

        let intoTask = try links.incomingBlocks(to: (.task, task.id))
        let intoProject = try links.incomingBlocks(to: (.project, project.id))
        #expect(intoTask.isEmpty)
        #expect(intoProject.contains { $0.fromID == blocker.id })
    }

    @MainActor
    @Test("labeled edge is repointed to the project")
    func repointsLabel() throws {
        let context = try makeContext()
        let task = insertTask(context, title: "Promote me")
        let labelRepo = LabelRepository(context: context)
        let label = try labelRepo.create(name: "feature", group: .domain)
        try labelRepo.assign(label, to: (.task, task.id))
        try context.save()

        let project = try ProjectPromoter(context: context).promoteToProject(task)

        #expect(try labelRepo.labels(for: (.task, task.id)).isEmpty)
        #expect(try labelRepo.labels(for: (.project, project.id)).contains { $0.id == label.id })
    }

    @MainActor
    @Test("promoting a task with a noteRef note reuses it: no dup containsTask edge, no orphan (P2)")
    func reusesExistingNoteWithoutDupEdges() throws {
        let context = try makeContext()
        // Note A with a checkbox -> reconcile mints T1 + a single containsTask edge.
        let notes = NoteRepository(context: context)
        let noteA = try notes.create(
            title: "Detail",
            blocks: MarkdownBlockParser.parse("- [ ] todo one"),
            role: .free
        )
        let links = LinkRepository(context: context)
        let containsBefore = try links.outgoing(from: (.note, noteA.id)).filter { $0.linkKind == .containsTask }
        #expect(containsBefore.count == 1)
        let t1ID = try #require(containsBefore.first?.toID)

        let task = insertTask(context, title: "Promote me")
        task.noteRef = noteA.id
        try context.save()

        let project = try ProjectPromoter(context: context).promoteToProject(task)

        // Note A is reused as the project page — not orphaned, not duplicated.
        #expect(project.canonicalNoteRef == noteA.id)
        #expect(noteA.deletedAt == nil)
        #expect(noteA.role == .projectPage)
        // Exactly ONE containsTask edge to T1 (the bug minted a second from a fresh note).
        let containsAfter = try context.fetch(FetchDescriptor<Link>())
            .filter { $0.linkKind == .containsTask && $0.toID == t1ID }
        #expect(containsAfter.count == 1)
        // No second project-page note was created.
        let projectPages = try context.fetch(FetchDescriptor<Note>())
            .filter { $0.role == .projectPage && $0.deletedAt == nil }
        #expect(projectPages.count == 1)
    }

    @MainActor
    @Test("promotion cascades the task's comments and scheduled blocks (P3)")
    func cascadesCommentsAndBlocks() throws {
        let context = try makeContext()
        let task = insertTask(context, title: "Promote me")
        try context.save()

        let comment = try CommentRepository(context: context).add(body: "note this", to: task.id, kind: .task)
        let block = try ScheduledBlockRepository(context: context).create(
            taskID: task.id,
            start: .now,
            end: Date.now.addingTimeInterval(1_800),
            status: .accepted,
            externalEventID: "evt-1"
        )

        _ = try ProjectPromoter(context: context).promoteToProject(task)

        #expect(comment.deletedAt != nil)
        #expect(block.deletedAt != nil)
        // The block's scheduledAs edge is gone — the graph no longer points at it.
        let blockID = block.id
        let edges = try context.fetch(FetchDescriptor<Link>())
            .filter { $0.toID == blockID && $0.linkKind == .scheduledAs }
        #expect(edges.isEmpty)
    }

    @MainActor
    @Test("promoting an already-deleted task throws and saves nothing")
    func deletedTaskThrows() throws {
        let context = try makeContext()
        let task = insertTask(context, title: "Gone")
        task.deletedAt = .now
        try context.save()

        let promoter = ProjectPromoter(context: context)
        #expect(throws: ProjectPromotionError.self) {
            try promoter.promoteToProject(task)
        }
        // No project was created.
        let projects = try context.fetch(FetchDescriptor<Project>())
        #expect(projects.isEmpty)
    }
}
