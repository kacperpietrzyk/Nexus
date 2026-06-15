import Foundation
import NexusCore

/// Pure derivation of the task fields produced when a knowledge-base note is
/// really an action item and the user picks "Convert to Task" (spec §6). The
/// caller inserts a `TaskItem` from this draft and soft-deletes the source note.
public enum NoteTaskConversion {
    public struct Draft: Equatable {
        public let title: String
        public let body: String
    }

    public static func draft(from note: Note) -> Draft {
        let trimmedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return Draft(title: trimmedTitle, body: note.plainText)
        }

        let firstLine =
            note.plainText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return Draft(title: firstLine.isEmpty ? "Untitled note" : firstLine, body: note.plainText)
    }
}
