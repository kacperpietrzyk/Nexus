import NexusCore
import Testing

@testable import NotesFeature

@Suite("NoteTaskConversion")
struct NoteTaskConversionTests {
    @Test("uses the note title when present")
    func titlePresent() {
        let n = Note(title: "Wysłać konto", plainText: "details here")
        let draft = NoteTaskConversion.draft(from: n)
        #expect(draft.title == "Wysłać konto")
        #expect(draft.body == "details here")
    }

    @Test("falls back to first non-empty line when title is empty")
    func titleFallback() {
        let n = Note(title: "  ", plainText: "Zadzwonić do Rafała\nmore")
        let draft = NoteTaskConversion.draft(from: n)
        #expect(draft.title == "Zadzwonić do Rafała")
    }

    @Test("falls back to Untitled note when title and text are empty")
    func emptyFallback() {
        let n = Note(title: "", plainText: "")
        #expect(NoteTaskConversion.draft(from: n).title == "Untitled note")
    }
}
