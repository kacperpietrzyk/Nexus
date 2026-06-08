import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
struct TaskNoteContentTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Note.self, TaskItem.self, Link.self, Project.self, Section.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func markdownUsesNoteContentBeforeLegacyBody() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Task", body: "legacy")
        let note = Note(
            title: "Task",
            contentData: try NoteContentCoder.encode([
                Block(kind: .heading(level: 2, runs: [InlineRun(text: "Heading")])),
                Block(kind: .paragraph(runs: [InlineRun(text: "Body")])),
            ])
        )
        task.noteRef = note.id
        context.insert(task)
        context.insert(note)
        try context.save()

        #expect(try TaskNoteContent.markdown(for: task, in: context) == "## Heading\n\nBody")
        #expect(try TaskNoteContent.plainText(for: task, in: context) == "Heading\nBody")
    }

    @Test func contentFallsBackToLegacyBodyWhenNoNoteExists() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Task", body: " legacy notes ")
        context.insert(task)
        try context.save()

        #expect(try TaskNoteContent.markdown(for: task, in: context) == "legacy notes")
        #expect(try TaskNoteContent.plainText(for: task, in: context) == "legacy notes")
    }

    @Test func replaceMarkdownCreatesAndUpdatesTaskContentNote() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Task", body: "legacy")
        context.insert(task)
        try context.save()

        try TaskNoteContent.replaceMarkdown("First", for: task, in: context)
        let noteID = try #require(task.noteRef)
        let created = try #require(try TaskNoteContent.note(for: task, in: context))

        #expect(created.id == noteID)
        #expect(created.plainText == "First")
        #expect(task.body.isEmpty)

        try TaskNoteContent.replaceMarkdown("Second", for: task, in: context)
        let updated = try #require(try TaskNoteContent.note(for: task, in: context))

        #expect(updated.id == noteID)
        #expect(updated.plainText == "Second")
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
    }

    @Test func replaceMarkdownClearsTaskContentNote() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Task")
        context.insert(task)
        try context.save()
        try TaskNoteContent.replaceMarkdown("To clear", for: task, in: context)
        let note = try #require(try TaskNoteContent.note(for: task, in: context))

        try TaskNoteContent.replaceMarkdown("   ", for: task, in: context)

        #expect(task.noteRef == nil)
        #expect(task.body.isEmpty)
        #expect(note.deletedAt != nil)
    }
}
