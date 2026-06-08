import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
struct NoteReconcilerTests {
    // MARK: - Harness

    private func makeContext() throws -> ModelContext {
        // Register every type the reconciler / repository fetches.
        let schema = Schema([Note.self, TaskItem.self, Link.self, Project.self, Section.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func insertNote(_ context: ModelContext, blocks: [Block], role: NoteRole = .free) throws -> Note {
        let note = Note(contentData: try NoteContentCoder.encode(blocks), role: role)
        context.insert(note)
        return note
    }

    private func outgoing(_ context: ModelContext, from noteID: UUID) throws -> [Link] {
        try context.fetch(FetchDescriptor<Link>()).filter { $0.fromID == noteID }
    }

    private func decode(_ note: Note) throws -> [Block] {
        try NoteContentCoder.decode(note.contentData)
    }

    // MARK: - plainText consistency (§6.4, §17)

    @Test func plainTextIsConsistentAfterReconcile() throws {
        let context = try makeContext()
        let blocks = [
            Block(kind: .heading(level: 1, runs: [InlineRun(text: "Title")])),
            Block(kind: .paragraph(runs: [InlineRun(text: "Hello "), InlineRun(text: "world", marks: [.bold])])),
            Block(kind: .divider),
        ]
        let note = try insertNote(context, blocks: blocks)
        let reconciler = NoteReconciler(context: context)

        try reconciler.reconcile(note)

        #expect(note.plainText == "Title\nHello world")
    }

    @Test func plainTextExcludesMarkdownSigils() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Buy milk")
        context.insert(task)
        let blocks = [Block(kind: .todo(taskRef: task.id, runs: [InlineRun(text: "Buy milk")]))]
        let note = try insertNote(context, blocks: blocks)

        try NoteReconciler(context: context).reconcile(note)

        #expect(note.plainText == "Buy milk")
        #expect(!note.plainText.contains("- [ ]"))
    }

    // MARK: - Idempotency (§17)

    @Test func reconcileIsIdempotent() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Existing")
        context.insert(task)
        let target = try insertNote(context, blocks: [])  // wikilink target by id
        let embedTarget = TaskItem(title: "Embedded")
        context.insert(embedTarget)

        let blocks = [
            Block(kind: .todo(taskRef: task.id, runs: [InlineRun(text: "Existing")])),
            Block(kind: .paragraph(runs: [InlineRun(text: "see", marks: [.link(ref: target.id, href: nil)])])),
            Block(kind: .embed(ref: embedTarget.id, kind: .note)),  // wrong kind on purpose
        ]
        let note = try insertNote(context, blocks: blocks)
        let reconciler = NoteReconciler(context: context)

        try reconciler.reconcile(note)
        try context.save()
        let firstPass = try outgoing(context, from: note.id)
            .map(\.idempotencyKey).sorted()

        // Second pass changes nothing.
        let changedAgain = try reconciler.reconcile(note)
        try context.save()
        let secondPass = try outgoing(context, from: note.id)
            .map(\.idempotencyKey).sorted()

        #expect(changedAgain == false)
        #expect(firstPass == secondPass)
        #expect(firstPass.count == 3)  // containsTask + mentions + embed
    }

    @Test func duplicateRefsCollapseToOneLink() throws {
        let context = try makeContext()
        let target = try insertNote(context, blocks: [])
        let blocks = [
            Block(kind: .paragraph(runs: [InlineRun(text: "a", marks: [.link(ref: target.id, href: nil)])])),
            Block(kind: .paragraph(runs: [InlineRun(text: "b", marks: [.link(ref: target.id, href: nil)])])),
        ]
        let note = try insertNote(context, blocks: blocks)

        try NoteReconciler(context: context).reconcile(note)
        try context.save()

        let mentions = try outgoing(context, from: note.id).filter { $0.linkKind == .mentions }
        #expect(mentions.count == 1)
    }

    @Test func embedKindIsCorrected() throws {
        let context = try makeContext()
        let project = Project(name: "Roadmap")
        context.insert(project)
        // Parser defaults embed kind to .note; reconciler must correct to .project.
        let note = try insertNote(context, blocks: [Block(kind: .embed(ref: project.id, kind: .note))])

        try NoteReconciler(context: context).reconcile(note)
        try context.save()

        let blocks = try decode(note)
        guard case .embed(_, let kind) = blocks[0].kind else { Issue.record("not embed"); return }
        #expect(kind == .project)
        let embedLinks = try outgoing(context, from: note.id).filter { $0.linkKind == .embed }
        #expect(embedLinks.first?.toKind == .project)
    }

    // MARK: - recompute-on-load repairs drift (§6.2, §17)

    @Test func recomputeRepairsMissingLinkDrift() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Task")
        context.insert(task)
        let note = try insertNote(
            context,
            blocks: [
                Block(kind: .todo(taskRef: task.id, runs: [InlineRun(text: "Task")]))
            ])
        let reconciler = NoteReconciler(context: context)
        try reconciler.reconcile(note)
        try context.save()

        // Simulate a crash that wrote the blob but lost the mirror: delete the link.
        for link in try outgoing(context, from: note.id) { context.delete(link) }
        try context.save()
        #expect(try outgoing(context, from: note.id).isEmpty)

        // Recompute repairs it.
        let changed = try reconciler.reconcile(note)
        try context.save()
        #expect(changed)
        #expect(try outgoing(context, from: note.id).filter { $0.linkKind == .containsTask }.count == 1)
    }

    @Test func recomputeRepairsStalePlainTextDrift() throws {
        let context = try makeContext()
        let note = try insertNote(
            context,
            blocks: [
                Block(kind: .paragraph(runs: [InlineRun(text: "Fresh")]))
            ])
        note.plainText = "Stale"  // inject drift

        let changed = try NoteReconciler(context: context).reconcile(note)
        #expect(changed)
        #expect(note.plainText == "Fresh")
    }

    @Test func reconcileRemovesOrphanedLink() throws {
        let context = try makeContext()
        let note = try insertNote(context, blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "x")]))])
        // An owned edge with no backing block: must be pruned.
        context.insert(Link(from: (.note, note.id), to: (.task, UUID()), linkKind: .containsTask))
        try context.save()

        let changed = try NoteReconciler(context: context).reconcile(note)
        try context.save()
        #expect(changed)
        #expect(try outgoing(context, from: note.id).isEmpty)
    }

    @Test func reconcileDedupesDuplicateMirrorRows() throws {
        let context = try makeContext()
        let task = TaskItem(title: "T")
        context.insert(task)
        let note = try insertNote(
            context,
            blocks: [Block(kind: .todo(taskRef: task.id, runs: [InlineRun(text: "T")]))]
        )
        // Inject two identical containsTask edges (drift): reconcile must collapse
        // them to exactly one and not thrash on the next pass.
        context.insert(Link(from: (.note, note.id), to: (.task, task.id), linkKind: .containsTask))
        context.insert(Link(from: (.note, note.id), to: (.task, task.id), linkKind: .containsTask))
        try context.save()

        let reconciler = NoteReconciler(context: context)
        let changed = try reconciler.reconcile(note)
        try context.save()
        #expect(changed)
        #expect(try outgoing(context, from: note.id).filter { $0.linkKind == .containsTask }.count == 1)
        #expect(try reconciler.reconcile(note) == false)
    }

    // MARK: - Checkbox lifecycle (§7, §8, §17)

    @Test func newTodoCreatesTaskWithBlockRefAsID() throws {
        let context = try makeContext()
        // Parser-minted placeholder ref, no backing TaskItem yet.
        let placeholder = UUID()
        let note = try insertNote(
            context,
            blocks: [
                Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "New todo")]))
            ])

        let changed = try NoteReconciler(context: context).reconcile(note)
        try context.save()

        // A TaskItem with id == placeholder was created (no blob rewrite needed).
        let task = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == placeholder }
        #expect(task != nil)
        #expect(task?.title == "New todo")
        #expect(task?.projectID == nil)  // free note → Inbox
        // Blob still carries the same placeholder ref (no rewrite on the new-todo path).
        let blocks = try decode(note)
        guard case .todo(let ref, _) = blocks[0].kind else { Issue.record("not todo"); return }
        #expect(ref == placeholder)
        // containsTask link exists.
        #expect(try outgoing(context, from: note.id).contains { $0.linkKind == .containsTask && $0.toID == placeholder })
        #expect(changed)
    }

    @Test func dailyNoteTodoDoesNotMintTaskOrEdge() throws {
        // SW1: a .dailyNote checkbox must stay an inert checkbox — no TaskItem, no
        // containsTask edge — so re-rendering a brief never spawns duplicate tasks.
        let context = try makeContext()
        let placeholder = UUID()
        let note = try insertNote(
            context,
            blocks: [Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "Follow up")]))],
            role: .dailyNote
        )

        _ = try NoteReconciler(context: context).reconcile(note)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TaskItem>()).isEmpty)
        #expect(try outgoing(context, from: note.id).contains { $0.linkKind == .containsTask } == false)
        // The block is left a todo (still renders as a checkbox).
        let blocks = try decode(note)
        guard case .todo = blocks[0].kind else { Issue.record("daily-note checkbox was rewritten"); return }
    }

    @Test func newTodoOnProjectPageLandsInProject() throws {
        let context = try makeContext()
        let project = Project(name: "P")
        context.insert(project)
        let placeholder = UUID()
        let note = try insertNote(
            context,
            blocks: [Block(kind: .todo(taskRef: placeholder, runs: [InlineRun(text: "Scoped")]))],
            role: .projectPage
        )
        project.canonicalNoteRef = note.id
        try context.save()

        try NoteReconciler(context: context).reconcile(note)
        try context.save()

        let task = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == placeholder }
        #expect(task?.projectID == project.id)
    }

    @Test func deletedTaskConvertsTodoToInertText() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Doomed")
        context.insert(task)
        let note = try insertNote(
            context,
            blocks: [
                Block(kind: .todo(taskRef: task.id, runs: [InlineRun(text: "Doomed")]))
            ])
        let reconciler = NoteReconciler(context: context)
        try reconciler.reconcile(note)  // establishes the containsTask memory edge
        try context.save()

        // The user deletes the task from the Tasks list.
        context.delete(task)
        try context.save()

        let changed = try reconciler.reconcile(note)
        try context.save()
        #expect(changed)

        // Block became an inert paragraph preserving the text — NOT still a todo
        // (else the next pass would recreate the task).
        let blocks = try decode(note)
        guard case .paragraph(let runs) = blocks[0].kind else {
            Issue.record("expected inert paragraph, got \(blocks[0].kind)")
            return
        }
        #expect(runs.first?.text == "Doomed")
        // Stale containsTask link removed.
        #expect(try outgoing(context, from: note.id).filter { $0.linkKind == .containsTask }.isEmpty)

        // And it stays converted (idempotent — no resurrection).
        let again = try reconciler.reconcile(note)
        #expect(again == false)
    }

    @Test func sameTaskInTwoNotesIsAllowed() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Shared")
        context.insert(task)
        let noteA = try insertNote(
            context,
            blocks: [
                Block(kind: .todo(taskRef: task.id, runs: [InlineRun(text: "Shared")]))
            ])
        let noteB = try insertNote(
            context,
            blocks: [
                Block(kind: .todo(taskRef: task.id, runs: [InlineRun(text: "Shared")]))
            ])
        let reconciler = NoteReconciler(context: context)

        try reconciler.reconcile(noteA)
        try reconciler.reconcile(noteB)
        try context.save()

        #expect(try outgoing(context, from: noteA.id).contains { $0.linkKind == .containsTask && $0.toID == task.id })
        #expect(try outgoing(context, from: noteB.id).contains { $0.linkKind == .containsTask && $0.toID == task.id })
        // Both todos still live (task exists), neither converted to inert.
        guard case .todo = (try decode(noteA))[0].kind, case .todo = (try decode(noteB))[0].kind else {
            Issue.record("a shared todo was wrongly converted")
            return
        }
    }

    // MARK: - Wikilink deferred resolution (§9, §17)

    @Test func pendingWikilinkBindsWhenTargetAppears() throws {
        let context = try makeContext()
        // Pending-by-name: link(ref: nil, href: nil), run text == title.
        let note = try insertNote(
            context,
            blocks: [
                Block(kind: .paragraph(runs: [InlineRun(text: "Roadmap", marks: [.link(ref: nil, href: nil)])]))
            ])
        let reconciler = NoteReconciler(context: context)

        // First pass: target doesn't exist → stays pending, no link row.
        try reconciler.reconcile(note)
        try context.save()
        #expect(try outgoing(context, from: note.id).filter { $0.linkKind == .mentions }.isEmpty)
        guard case .paragraph(let runs0) = (try decode(note))[0].kind,
            case .link(let ref0, _) = runs0[0].marks[0]
        else { Issue.record("link gone"); return }
        #expect(ref0 == nil)  // still pending

        // The target appears.
        let target = try insertNote(context, blocks: [])
        target.title = "Roadmap"
        try context.save()

        // Next recompute binds the ref + creates the mentions link.
        let changed = try reconciler.reconcile(note)
        try context.save()
        #expect(changed)

        guard case .paragraph(let runs1) = (try decode(note))[0].kind,
            case .link(let ref1, _) = runs1[0].marks[0]
        else { Issue.record("link gone"); return }
        #expect(ref1 == target.id)
        #expect(try outgoing(context, from: note.id).contains { $0.linkKind == .mentions && $0.toID == target.id })

        // Bound link never re-resolves (idempotent).
        #expect(try reconciler.reconcile(note) == false)
    }

    @Test func unresolvedWikilinkProducesNoLink() throws {
        let context = try makeContext()
        let note = try insertNote(
            context,
            blocks: [
                Block(kind: .paragraph(runs: [InlineRun(text: "Ghost", marks: [.link(ref: nil, href: nil)])]))
            ])
        let reconciler = NoteReconciler(context: context)

        try reconciler.reconcile(note)
        try context.save()
        // Stable across passes: still no link, still pending.
        #expect(try reconciler.reconcile(note) == false)
        #expect(try outgoing(context, from: note.id).isEmpty)
    }
}
