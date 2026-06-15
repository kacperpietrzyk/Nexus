import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NotesFeature

/// Model-level wiring for inline link insertion (GAP #6): a spliced `.link(ref:)`
/// run must persist through `NoteEditorModel` and be mirrored as a `mentions` edge
/// by the reconciler (the same contract `updateContentReconcilesNewGraph` proves at
/// the repo level). Uses a real in-memory container so the persistence + reconcile
/// path is exercised end to end, not just the pure splice.
@MainActor
@Suite("NoteEditorModel inline link")
struct NoteEditorModelInlineLinkTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Note.self, TaskItem.self, Link.self, Project.self, Section.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func insertInlineLinkPersistsRunAndMirrorsMentionsEdge() throws {
        let context = try makeContext()
        let repo = NoteRepository(context: context)
        let target = try repo.create(title: "Target", blocks: [])
        let source = try repo.create(
            blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "")]))]
        )
        let blockID = try NoteContentCoder.decode(source.contentData).first!.id

        let model = NoteEditorModel(note: source, repository: repo)
        let candidate = LinkCandidate(id: target.id, kind: .note, title: "Target")
        let draft = "see [[Tar"
        let trigger = InlineLinkInsertion.detectTrigger(in: draft)!

        model.insertInlineLink(to: candidate, trigger: trigger, draft: draft, forBlock: blockID)

        // The block now carries a link run pointing at the target by id.
        guard case .paragraph(let runs)? = model.blocks.first(where: { $0.id == blockID })?.kind else {
            Issue.record("expected the source block to still be a paragraph")
            return
        }
        let linkMark: Mark = .link(ref: target.id, href: nil)
        #expect(runs.contains { $0.marks.contains(linkMark) })

        // The reconciler mirrored the run as an outgoing `mentions` edge.
        let edges = try context.fetch(FetchDescriptor<Link>()).filter { $0.fromID == source.id }
        #expect(edges.contains { $0.linkKind == .mentions && $0.toID == target.id })
    }

    @Test func wrapSelectionAsLinkPersistsRun() throws {
        let context = try makeContext()
        let repo = NoteRepository(context: context)
        let target = try repo.create(title: "Hub", blocks: [])
        let source = try repo.create(
            blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "go here now")]))]
        )
        let blockID = try NoteContentCoder.decode(source.contentData).first!.id

        let model = NoteEditorModel(note: source, repository: repo)
        let candidate = LinkCandidate(id: target.id, kind: .note, title: "Hub")

        model.wrapSelectionAsLink(to: candidate, text: "go here now", range: 3..<7, forBlock: blockID)

        let edges = try context.fetch(FetchDescriptor<Link>()).filter { $0.fromID == source.id }
        #expect(edges.contains { $0.linkKind == .mentions && $0.toID == target.id })
    }
}
