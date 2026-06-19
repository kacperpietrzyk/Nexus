import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("NoteListResolver")
@MainActor
struct NoteListResolverTests {

    private func note(
        _ title: String,
        role: NoteRole = .free,
        folder: String? = nil,
        pinned: Bool = false,
        pinnedAt: Date? = nil,
        updated: Date = Date(timeIntervalSince1970: 0)
    ) -> Note {
        let n = Note(title: title, role: role)
        n.folderPath = folder
        n.isPinned = pinned
        n.pinnedAt = pinnedAt
        n.updatedAt = updated
        return n
    }

    @Test("overview = Pinned (pinnedAt desc) then Recent (updatedAt desc), templates + pinned excluded from Recent")
    func overview() {
        let pinnedOld = note("P-old", pinned: true, pinnedAt: Date(timeIntervalSince1970: 10))
        let pinnedNew = note("P-new", pinned: true, pinnedAt: Date(timeIntervalSince1970: 20))
        let recentA = note("A", updated: Date(timeIntervalSince1970: 100))
        let recentB = note("B", updated: Date(timeIntervalSince1970: 200))
        let template = note("T", role: .template, updated: Date(timeIntervalSince1970: 999))
        let all = [pinnedOld, recentA, template, pinnedNew, recentB]
        let tree = NoteTreeModel.build(notes: all, links: [], projects: [])

        let result = NoteListResolver.resolve(
            container: .overview, tree: tree, allNotes: all, recentLimit: 50)

        #expect(result.sections.count == 2)
        #expect(result.sections[0].title == "Pinned")
        #expect(result.sections[0].notes.map(\.title) == ["P-new", "P-old"])
        #expect(result.sections[1].title == "Recent")
        #expect(result.sections[1].notes.map(\.title) == ["B", "A"])
        #expect(result.truncated == false)
    }

    @Test("overview Recent honors recentLimit and reports truncation")
    func overviewTruncates() {
        let notes = (0..<5).map { note("N\($0)", updated: Date(timeIntervalSince1970: Double($0))) }
        let tree = NoteTreeModel.build(notes: notes, links: [], projects: [])
        let result = NoteListResolver.resolve(
            container: .overview, tree: tree, allNotes: notes, recentLimit: 3)
        let recent = result.sections.first { $0.title == "Recent" }
        #expect(recent?.notes.count == 3)
        #expect(result.truncated == true)
    }

    @Test("folder container = notes directly at that path (single ungrouped section, no header)")
    func folder() {
        let atPath = note("at", folder: "clients/knauf", updated: Date(timeIntervalSince1970: 2))
        let deeper = note("deeper", folder: "clients/knauf/meetings", updated: Date(timeIntervalSince1970: 3))
        let other = note("other", folder: "clients/acme")
        let all = [atPath, deeper, other]
        let tree = NoteTreeModel.build(notes: all, links: [], projects: [])

        let result = NoteListResolver.resolve(
            container: .folder("clients/knauf"), tree: tree, allNotes: all, recentLimit: 50)

        #expect(result.sections.count == 1)
        #expect(result.sections[0].title == nil)
        #expect(result.sections[0].notes.map(\.title) == ["at"])
    }

    @Test("project container: canonical note always first, then linked notes by updatedAt desc")
    func projectCanonicalFirst() throws {
        let projectID = UUID()
        // Canonical has an older updatedAt — the old "sort all together" logic would NOT put
        // it first. The new logic pins it at position 0 regardless of date.
        let canonical = note("Project page", role: .projectPage, updated: Date(timeIntervalSince1970: 1))
        let linked1 = note("Linked A", updated: Date(timeIntervalSince1970: 100))
        let linked2 = note("Linked B", updated: Date(timeIntervalSince1970: 200))

        func projectLink(note noteID: UUID, project projectID: UUID) -> Link {
            Link(from: (.note, noteID), to: (.project, projectID), linkKind: .mentions)
        }

        let proj = NoteTreeModel.ProjectRef(id: projectID, title: "Test Project", canonicalNoteRef: canonical.id)
        let tree = NoteTreeModel.build(
            notes: [canonical, linked1, linked2],
            links: [
                projectLink(note: canonical.id, project: projectID),
                projectLink(note: linked1.id, project: projectID),
                projectLink(note: linked2.id, project: projectID),
            ],
            projects: [proj]
        )

        let result = NoteListResolver.resolve(
            container: .project(projectID), tree: tree, allNotes: [canonical, linked1, linked2],
            recentLimit: 50)

        #expect(result.sections.count == 1)
        let notes = result.sections[0].notes
        // Canonical must be first despite having the oldest updatedAt.
        #expect(notes.first?.id == canonical.id)
        // Remaining notes are updatedAt desc: Linked B (200) before Linked A (100).
        #expect(notes.map(\.title) == ["Project page", "Linked B", "Linked A"])
    }

    @Test("unfiled / journal / templates pull the matching tree slice, updatedAt desc")
    func structuralSlices() {
        let u1 = note("u1", updated: Date(timeIntervalSince1970: 1))
        let u2 = note("u2", updated: Date(timeIntervalSince1970: 2))
        let daily = note("d", role: .dailyNote)
        let tmpl = note("t", role: .template)
        let all = [u1, daily, tmpl, u2]
        let tree = NoteTreeModel.build(notes: all, links: [], projects: [])

        let unfiled = NoteListResolver.resolve(
            container: .unfiled, tree: tree, allNotes: all, recentLimit: 50)
        #expect(unfiled.sections.count == 1)
        #expect(unfiled.sections[0].notes.map(\.title) == ["u2", "u1"])

        let templates = NoteListResolver.resolve(
            container: .templates, tree: tree, allNotes: all, recentLimit: 50)
        #expect(templates.sections[0].notes.map(\.title) == ["t"])
    }
}
