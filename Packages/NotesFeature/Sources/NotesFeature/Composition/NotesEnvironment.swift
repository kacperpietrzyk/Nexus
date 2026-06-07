import NexusCore
import SwiftUI

private struct NoteRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: NoteRepository? = nil
}

extension EnvironmentValues {
    /// Injected by app composition roots. `@MainActor`-bound because
    /// `NoteRepository` is `@MainActor`. Views access via
    /// `@Environment(\.noteRepository)`. Mirrors `\.taskRepository`.
    public var noteRepository: NoteRepository? {
        get { self[NoteRepositoryEnvironmentKey.self] }
        set { self[NoteRepositoryEnvironmentKey.self] = newValue }
    }
}
