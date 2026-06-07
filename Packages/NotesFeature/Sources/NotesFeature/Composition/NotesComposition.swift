import Foundation
import NexusCore
import SwiftData

/// Factory for the production `NoteRepository`, mirroring `TasksComposition`.
/// Apps call this once from their composition root and inject the result into the
/// SwiftUI environment so every Notes surface shares a single repository identity
/// (one `ModelContext`, one reconciler).
public enum NotesComposition {

    /// Builds the production `NoteRepository` for an app's main `ModelContext`.
    ///
    /// `tasks` is the app's existing `TaskItemRepository`. The repository needs it
    /// for the full checkbox→Task lifecycle (recurrence side-effects, notifications)
    /// when a todo block is toggled (spec §7). Pass the same instance the Tasks
    /// surface uses so a completion in a note and a completion in the task list go
    /// through one code path.
    @MainActor
    public static func makeRepository(
        for context: ModelContext,
        tasks: TaskItemRepository
    ) -> NoteRepository {
        NoteRepository(context: context, tasks: tasks, now: { .now })
    }
}
