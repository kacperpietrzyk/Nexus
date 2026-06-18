import NexusCore
import Testing

@testable import NotesFeature

@Suite("NoteMarkdownExport")
struct NoteMarkdownExportTests {

    @Test("markdown includes title as h1")
    func titleBecomesHeading() {
        let note = Note(title: "My Note", plainText: "some body text")
        let md = NoteMarkdownExport.markdown(for: note)
        #expect(md.hasPrefix("# My Note"))
    }

    @Test("untitled note uses 'Untitled' heading")
    func untitledFallback() {
        let note = Note(title: "", plainText: "body")
        let md = NoteMarkdownExport.markdown(for: note)
        #expect(md.hasPrefix("# Untitled"))
    }

    @Test("folder metadata appears as bullet")
    func folderMetadata() {
        let note = Note(title: "Spec", plainText: "")
        note.folderPath = "projects/nexus"
        let md = NoteMarkdownExport.markdown(for: note)
        #expect(md.contains("- Folder: projects/nexus"))
    }

    @Test("tags metadata appears as bullet")
    func tagsMetadata() {
        let note = Note(title: "Tagged", plainText: "", tags: ["swift", "design"])
        let md = NoteMarkdownExport.markdown(for: note)
        #expect(md.contains("- Tags:"))
        #expect(md.contains("swift"))
    }

    @Test("body text is included")
    func bodyIsIncluded() {
        let note = Note(title: "Title", plainText: "paragraph text")
        let md = NoteMarkdownExport.markdown(for: note)
        #expect(md.contains("paragraph text"))
    }

    @Test("wikilink uses double-bracket syntax")
    func wikilinkFormat() {
        let note = Note(title: "My Note", plainText: "")
        #expect(NoteMarkdownExport.wikilink(for: note) == "[[My Note]]")
    }

    @Test("wikilink falls back to Untitled for empty title")
    func wikilinkUntitled() {
        let note = Note(title: "", plainText: "")
        #expect(NoteMarkdownExport.wikilink(for: note) == "[[Untitled]]")
    }
}
