import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

/// Characterization: the predicated note-text fetch (FIX 2) must produce a map
/// byte-identical to the old "fetch ALL notes then filter in memory" path —
/// same keys, same text — while only touching the few notes referenced.
@MainActor
@Suite("Task inbox note-text fetch")
struct TaskInboxNoteTextTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, Note.self, configurations: config)
        return ModelContext(container)
    }

    /// Reference implementation = the pre-FIX behavior (fetch all, filter in memory).
    private func referenceMap(for tasks: [TaskItem], in context: ModelContext) -> [UUID: String] {
        let noteIDs = Set(tasks.compactMap(\.noteRef))
        guard !noteIDs.isEmpty else { return [:] }
        guard let notes = try? context.fetch(FetchDescriptor<Note>()) else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: notes.compactMap { note in
                guard note.deletedAt == nil, noteIDs.contains(note.id) else { return nil }
                if !note.plainText.isEmpty {
                    return (note.id, note.plainText)
                }
                let text =
                    (try? NotePlainTextFlattener.plainText(for: NoteContentCoder.decode(note.contentData)))
                    ?? ""
                return (note.id, text)
            }
        )
    }

    @Test("predicated fetch equals all-fetch map for referenced notes")
    func predicatedMatchesAllFetch() throws {
        let context = try makeContext()

        let noteA = Note(title: "A")
        noteA.plainText = "alpha body"
        let noteB = Note(title: "B")
        noteB.plainText = "beta body"
        let noteUnreferenced = Note(title: "C")
        noteUnreferenced.plainText = "gamma body"
        let noteDeleted = Note(title: "D")
        noteDeleted.plainText = "deleted body"
        noteDeleted.deletedAt = .now
        context.insert(noteA)
        context.insert(noteB)
        context.insert(noteUnreferenced)
        context.insert(noteDeleted)

        let taskA = TaskItem(title: "task A", noteRef: noteA.id)
        let taskB = TaskItem(title: "task B", noteRef: noteB.id)
        let taskNoRef = TaskItem(title: "task plain")
        let taskDeletedRef = TaskItem(title: "task deleted ref", noteRef: noteDeleted.id)
        context.insert(taskA)
        context.insert(taskB)
        context.insert(taskNoRef)
        context.insert(taskDeletedRef)
        try context.save()

        let tasks = [taskA, taskB, taskNoRef, taskDeletedRef]
        let expected = referenceMap(for: tasks, in: context)
        let actual = taskInboxNoteTextByID(for: tasks, in: context)

        #expect(actual == expected)
        // Sanity: referenced live notes present, unreferenced + deleted absent.
        #expect(actual[noteA.id] == "alpha body")
        #expect(actual[noteB.id] == "beta body")
        #expect(actual[noteUnreferenced.id] == nil)
        #expect(actual[noteDeleted.id] == nil)
    }

    @Test("empty when no task carries a note reference")
    func emptyWhenNoReferences() throws {
        let context = try makeContext()
        let note = Note(title: "orphan")
        note.plainText = "x"
        context.insert(note)
        let task = TaskItem(title: "no ref")
        context.insert(task)
        try context.save()

        #expect(taskInboxNoteTextByID(for: [task], in: context).isEmpty)
    }

    @Test("falls back to flattened content when plainText is empty")
    func fallsBackToFlattenedContent() throws {
        let context = try makeContext()
        // plainText left empty -> must flatten contentData, same as old path.
        let note = Note(title: "rich")
        context.insert(note)
        let task = TaskItem(title: "task", noteRef: note.id)
        context.insert(task)
        try context.save()

        let expected = referenceMap(for: [task], in: context)
        let actual = taskInboxNoteTextByID(for: [task], in: context)
        #expect(actual == expected)
        #expect(actual[note.id] != nil)
    }
}
