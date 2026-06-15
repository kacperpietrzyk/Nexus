import NexusCore
import SwiftUI

private struct NoteRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: NoteRepository? = nil
}

private struct NotesTaskRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: TaskItemRepository? = nil
}

extension EnvironmentValues {
    /// Injected by app composition roots. `@MainActor`-bound because
    /// `NoteRepository` is `@MainActor`. Views access via
    /// `@Environment(\.noteRepository)`. Mirrors `\.taskRepository`.
    public var noteRepository: NoteRepository? {
        get { self[NoteRepositoryEnvironmentKey.self] }
        set { self[NoteRepositoryEnvironmentKey.self] = newValue }
    }

    /// Injected by app composition roots so the Notes tree can convert a
    /// note into a task. Distinct from TasksFeature's `\.taskRepository` to
    /// avoid an `EnvironmentValues` member collision where both modules are
    /// imported. `TaskItemRepository` is `@MainActor`.
    public var notesTaskRepository: TaskItemRepository? {
        get { self[NotesTaskRepositoryEnvironmentKey.self] }
        set { self[NotesTaskRepositoryEnvironmentKey.self] = newValue }
    }
}
