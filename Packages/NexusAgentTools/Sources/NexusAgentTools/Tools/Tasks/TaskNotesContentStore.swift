import Foundation
import NexusCore

@MainActor
enum TaskNotesContentStore {
    static func replaceNotes(_ notes: String?, for task: TaskItem, context: AgentContext) throws {
        try TaskNoteContent.replaceMarkdown(
            notes,
            for: task,
            in: context.modelContext.context,
            repository: context.noteRepository,
            now: context.now
        )
    }

    static func dto(for task: TaskItem, context: AgentContext) throws -> TaskDTO {
        try TaskDTO(from: task, modelContext: context.modelContext.context)
    }
}
