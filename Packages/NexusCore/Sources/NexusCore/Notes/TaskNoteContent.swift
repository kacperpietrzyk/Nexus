import Foundation
import SwiftData

@MainActor
public enum TaskNoteContent {
    public static func note(for task: TaskItem, in context: ModelContext) throws -> Note? {
        guard let noteID = task.noteRef else { return nil }
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public static func markdown(for task: TaskItem, in context: ModelContext) throws -> String {
        if let note = try note(for: task, in: context) {
            return try BlockMarkdownSerializer.markdown(for: NoteContentCoder.decode(note.contentData))
        }
        return task.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func plainText(for task: TaskItem, in context: ModelContext) throws -> String {
        if let note = try note(for: task, in: context) {
            if !note.plainText.isEmpty {
                return note.plainText
            }
            return try NotePlainTextFlattener.plainText(for: NoteContentCoder.decode(note.contentData))
        }
        return task.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func replaceMarkdown(
        _ markdown: String?,
        for task: TaskItem,
        in context: ModelContext,
        repository: NoteRepository? = nil,
        now: @escaping () -> Date = Date.init
    ) throws {
        let text = markdown?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let noteRepository = repository ?? NoteRepository(context: context, now: now)
        if text.isEmpty {
            try clear(for: task, in: context, repository: noteRepository, now: now)
            return
        }

        let blocks = MarkdownBlockParser.parse(text)
        if let note = try note(for: task, in: context) {
            try noteRepository.updateFields(note, title: task.title, role: NoteRole.free)
            try noteRepository.updateContent(note, blocks: blocks)
        } else {
            let note = try noteRepository.create(title: task.title, blocks: blocks, role: NoteRole.free)
            task.noteRef = note.id
        }
        task.body = ""
        task.updatedAt = now()
        try context.save()
    }

    private static func clear(
        for task: TaskItem,
        in context: ModelContext,
        repository: NoteRepository,
        now: () -> Date
    ) throws {
        if let note = try note(for: task, in: context) {
            try repository.delete(note)
        }
        task.noteRef = nil
        task.body = ""
        task.updatedAt = now()
        try context.save()
    }
}
