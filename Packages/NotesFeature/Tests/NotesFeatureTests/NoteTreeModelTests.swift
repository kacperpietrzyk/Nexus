import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("NoteTreeModel")
struct NoteTreeModelTests {
    private func note(
        _ title: String,
        role: NoteRole = .free,
        folder: String? = nil,
        deleted: Bool = false
    ) -> Note {
        let n = Note(title: title, role: role)
        n.folderPath = folder
        if deleted { n.deletedAt = .now }
        return n
    }

    private func projectLink(note noteID: UUID, project projectID: UUID) -> Link {
        Link(from: (.note, noteID), to: (.project, projectID), linkKind: .mentions)
    }

    @Test("unfiled holds free notes with no folder and no project link")
    func unfiled() {
        let a = note("loose")
        let b = note("filed", folder: "Klienci")
        let tree = NoteTreeModel.build(notes: [a, b], links: [], projects: [])
        #expect(tree.unfiled.map(\.id) == [a.id])
    }

    @Test("a project-linked loose note is NOT in unfiled (lives under Projects)")
    func projectLooseNoteLeavesUnfiled() {
        let projectID = UUID()
        let n = note("linked-loose")
        let proj = NoteTreeModel.ProjectRef(id: projectID, title: "Audit", canonicalNoteRef: nil)
        let tree = NoteTreeModel.build(
            notes: [n],
            links: [projectLink(note: n.id, project: projectID)],
            projects: [proj]
        )
        #expect(tree.unfiled.isEmpty)
        #expect(tree.projects.first?.notes.map(\.id) == [n.id])
    }

    @Test("projects: canonical first, then linked, de-duplicated")
    func projectsSection() throws {
        let projectID = UUID()
        let canonical = note("Project page", role: .projectPage)
        let linked = note("Plan")
        let proj = NoteTreeModel.ProjectRef(id: projectID, title: "Audit", canonicalNoteRef: canonical.id)
        let tree = NoteTreeModel.build(
            notes: [canonical, linked],
            links: [
                projectLink(note: canonical.id, project: projectID),
                projectLink(note: linked.id, project: projectID),
            ],
            projects: [proj]
        )
        let section = try #require(tree.projects.first)
        #expect(section.canonical?.id == canonical.id)
        #expect(section.notes.map(\.id) == [linked.id])
    }

    @Test("library nests folders and creates intermediate nodes")
    func libraryNesting() throws {
        let deep = note("deep", folder: "a/b/c")
        let tree = NoteTreeModel.build(notes: [deep], links: [], projects: [])
        let a = try #require(tree.library.first)
        #expect(a.name == "a")
        let b = try #require(a.children.first)
        #expect(b.name == "b")
        let c = try #require(b.children.first)
        #expect(c.name == "c")
        #expect(c.notes.map(\.id) == [deep.id])
    }

    @Test("a folderPath that normalizes to nil lands in unfiled, not lost")
    func folderPathNormalizingToNilStaysUnfiled() {
        // " " / "." / "///" are `!= nil` raw but normalize to root — must NOT
        // vanish from every bucket.
        let blank = note("blank", folder: "   ")
        let dot = note("dot", folder: ".")
        let slashes = note("slashes", folder: "///")
        let tree = NoteTreeModel.build(notes: [blank, dot, slashes], links: [], projects: [])
        #expect(tree.unfiled.map(\.id) == [blank.id, dot.id, slashes.id])
        #expect(tree.library.isEmpty)
    }

    @Test("journal and templates bucket by role; tombstones excluded everywhere")
    func journalTemplatesAndTombstones() {
        let daily = note("2026-06-14", role: .dailyNote)
        let tmpl = note("Meeting tmpl", role: .template)
        let dead = note("dead", deleted: true)
        let tree = NoteTreeModel.build(notes: [daily, tmpl, dead], links: [], projects: [])
        #expect(tree.journal.map(\.id) == [daily.id])
        #expect(tree.templates.map(\.id) == [tmpl.id])
        #expect(tree.unfiled.isEmpty)
    }
}
