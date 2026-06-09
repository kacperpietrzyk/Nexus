import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("NoteListGrouping")
struct NoteListGroupingTests {

    // MARK: - Tag normalization / round-trip (A2)

    @Test("normalizedTags trims, strips leading #, drops empties, dedupes case-insensitively")
    func normalize() {
        let result = NoteListGrouping.normalizedTags([
            "  backend ", "#api", "API", "", "   ", "design",
        ])
        #expect(result == ["backend", "api", "design"])
    }

    @Test("addTag appends a new tag and is a no-op for a duplicate")
    func addTag() {
        let base = ["backend"]
        #expect(NoteListGrouping.addTag("#api", to: base) == ["backend", "api"])
        #expect(NoteListGrouping.addTag("BACKEND", to: base) == ["backend"])
        #expect(NoteListGrouping.addTag("   ", to: base) == ["backend"])
    }

    @Test("removeTag drops the matching tag case-insensitively")
    func removeTag() {
        let base = ["backend", "api", "design"]
        #expect(NoteListGrouping.removeTag("API", from: base) == ["backend", "design"])
        #expect(NoteListGrouping.removeTag("missing", from: base) == base)
    }

    @Test("tag edit round-trips: add then remove returns the original normalized set")
    func tagRoundTrip() {
        let start = ["backend", "api"]
        let added = NoteListGrouping.addTag("design", to: start)
        let back = NoteListGrouping.removeTag("design", from: added)
        #expect(back == start)
    }

    // MARK: - Grouping by role (A1)

    @Test("groups(by: .role) buckets notes in fixed role order, omitting empty roles")
    @MainActor
    func roleGroups() {
        let freeNote = Note(title: "Free", role: .free)
        let pageNote = Note(title: "Page", role: .projectPage)
        let dailyNote = Note(title: "Daily", role: .dailyNote)

        // Deliberately out of role order on input.
        let groups = NoteListGrouping.groups(for: [dailyNote, pageNote, freeNote], mode: .role)

        #expect(groups.map(\.id) == ["free", "projectPage", "dailyNote"])
        #expect(groups.map(\.title) == ["Notes", "Project Pages", "Daily Notes"])
        #expect(groups.first?.notes.map(\.id) == [freeNote.id])
    }

    @Test("groups(by: .role) omits roles with no notes")
    @MainActor
    func roleGroupsOmitsEmpty() {
        let freeNote = Note(title: "A", role: .free)
        let groups = NoteListGrouping.groups(for: [freeNote], mode: .role)
        #expect(groups.count == 1)
        #expect(groups.first?.id == "free")
    }

    // MARK: - Grouping by tag (A1)

    @Test("groups(by: .tag) sorts tags alphabetically, puts untagged last, fans a note across tags")
    @MainActor
    func tagGroups() {
        let multiTag = Note(title: "A", tags: ["zeta", "alpha"])
        let oneTag = Note(title: "B", tags: ["alpha"])
        let noTag = Note(title: "C", tags: [])

        let groups = NoteListGrouping.groups(for: [multiTag, oneTag, noTag], mode: .tag)

        #expect(groups.map(\.id) == ["alpha", "zeta", NoteListGrouping.untaggedGroupID])
        #expect(groups.map(\.title) == ["#alpha", "#zeta", "No tags"])
        // `multiTag` appears under both alpha and zeta; `oneTag` only under alpha.
        let alpha = groups.first { $0.id == "alpha" }
        #expect(alpha?.notes.map(\.id) == [multiTag.id, oneTag.id])
        let untagged = groups.first { $0.id == NoteListGrouping.untaggedGroupID }
        #expect(untagged?.notes.map(\.id) == [noTag.id])
    }

    @Test("groups(by: .tag) has no untagged section when every note is tagged")
    @MainActor
    func tagGroupsNoUntagged() {
        let tagged = Note(title: "A", tags: ["x"])
        let groups = NoteListGrouping.groups(for: [tagged], mode: .tag)
        #expect(groups.map(\.id) == ["x"])
    }

    // MARK: - Backlink counts (A5)

    @Test("backlinkCounts folds only note-targeted links into a per-note count map")
    @MainActor
    func backlinkCounts() {
        let noteA = UUID()
        let noteB = UUID()
        let source = UUID()
        let taskID = UUID()

        let links: [GraphLink] = [
            Link(from: (.note, source), to: (.note, noteA), linkKind: .mentions),
            Link(from: (.note, source), to: (.note, noteA), linkKind: .embed),
            Link(from: (.note, source), to: (.note, noteB), linkKind: .mentions),
            // A non-note target must not be counted toward any note.
            Link(from: (.note, source), to: (.task, taskID), linkKind: .mentions),
        ]

        let counts = NoteListGrouping.backlinkCounts(from: links)
        #expect(counts[noteA] == 2)
        #expect(counts[noteB] == 1)
        #expect(counts[taskID] == nil)
    }
}
