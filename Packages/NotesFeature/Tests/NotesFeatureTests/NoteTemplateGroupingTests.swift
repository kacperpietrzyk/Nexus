import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("Note templates — list grouping")
struct NoteTemplateGroupingTests {
    private func note(_ title: String, role: NoteRole, tags: [String] = []) -> Note {
        let note = Note(title: title, role: role, tags: tags)
        return note
    }

    @Test("role mode surfaces templates in their own trailing section")
    func roleModeHasTemplatesSection() {
        let notes = [
            note("free", role: .free),
            note("tpl", role: .template),
        ]
        let groups = NoteListGrouping.groups(for: notes, mode: .role)
        #expect(groups.map(\.title) == ["Notes", "Templates"])
        #expect(groups.last?.notes.map(\.title) == ["tpl"])
    }

    @Test("tag mode excludes templates entirely")
    func tagModeExcludesTemplates() {
        let notes = [
            note("free", role: .free, tags: ["work"]),
            note("tpl", role: .template, tags: ["work"]),
        ]
        let groups = NoteListGrouping.groups(for: notes, mode: .tag)
        #expect(groups.count == 1)
        #expect(groups[0].notes.map(\.title) == ["free"])
    }

    @Test("roleTitle for .template")
    func roleTitle() {
        #expect(NoteListGrouping.roleTitle(.template) == "Templates")
    }
}
