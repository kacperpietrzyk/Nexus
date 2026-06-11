import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("Note templates (NoteRole.template)")
struct NoteTemplateTests {
    @MainActor
    private func makeRepo() throws -> NoteRepository {
        let schema = Schema([Note.self, TaskItem.self, Link.self, Project.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return NoteRepository(context: ModelContext(container))
    }

    @MainActor
    @Test("instantiateTemplate copies content into a fresh .free note")
    func instantiateCopiesIntoFreeNote() throws {
        let repo = try makeRepo()
        let template = try repo.create(
            title: "Meeting notes scaffold",
            blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "Agenda")]))],
            role: .template,
            tags: ["meetings"]
        )
        template.folderPath = "work/meetings"
        template.propertiesJSON = #"[{"key":"status","value":{"string":{"_0":"draft"}}}]"#
        try repo.context.save()

        let copy = try repo.instantiateTemplate(template)

        #expect(copy.id != template.id)
        #expect(copy.role == .free)
        #expect(copy.title == "Meeting notes scaffold")
        #expect(copy.tags == ["meetings"])
        #expect(copy.contentData == template.contentData)
        #expect(copy.plainText == template.plainText)
        #expect(copy.folderPath == "work/meetings")
        #expect(copy.propertiesJSON == template.propertiesJSON)
        // Template untouched.
        #expect(template.role == .template)
        // Both rows live.
        let notes = try repo.context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 2)
    }

    @MainActor
    @Test("instantiateTemplate rejects non-template notes")
    func instantiateRejectsNonTemplate() throws {
        let repo = try makeRepo()
        let free = try repo.create(title: "Just a note")

        #expect(throws: NoteTemplateError.notATemplate(noteID: free.id)) {
            try repo.instantiateTemplate(free)
        }
    }
}
