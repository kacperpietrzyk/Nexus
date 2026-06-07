import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("Note")
struct NoteTests {
    @Test("init sets defaults")
    func defaults() {
        let note = Note()
        #expect(note.title.isEmpty)
        #expect(note.contentData.isEmpty)
        #expect(note.plainText.isEmpty)
        #expect(note.role == .free)
        #expect(note.tags.isEmpty)
        #expect(note.deletedAt == nil)
        #expect(note.kind == .note)
        #expect(note.createdAt == note.updatedAt)
    }

    @Test("init can override fields")
    func overrides() {
        let id = UUID()
        let blob = Data("blob".utf8)
        let note = Note(
            id: id,
            title: "Meeting prep",
            contentData: blob,
            plainText: "agenda items",
            role: .projectPage,
            tags: ["work"]
        )
        #expect(note.id == id)
        #expect(note.title == "Meeting prep")
        #expect(note.contentData == blob)
        #expect(note.plainText == "agenda items")
        #expect(note.role == .projectPage)
        #expect(note.tags == ["work"])
    }

    @Test("Searchable returns plainText")
    func searchableTextIsPlainText() {
        let note = Note(title: "Title ignored for search", plainText: "the flat content")
        #expect(note.searchableText == "the flat content")
    }

    @Test("conforms to Linkable with kind note")
    func conformsToLinkable() {
        let note: any Linkable = Note(title: "x")
        #expect(note.kind == .note)
    }

    @MainActor
    @Test("can be inserted into in-memory ModelContainer")
    func insertable() throws {
        let schema = Schema([Note.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.insert(Note(title: "first note", plainText: "body text"))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "first note")
        #expect(fetched.first?.plainText == "body text")
    }
}
