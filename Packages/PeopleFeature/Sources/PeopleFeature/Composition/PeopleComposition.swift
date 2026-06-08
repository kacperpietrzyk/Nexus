import Foundation
import NexusCore
import SwiftData

/// Factory for the production `PersonRepository`, mirroring `NotesComposition`.
/// Apps call this once from their composition root and inject the result into the
/// SwiftUI environment so every People surface shares a single repository identity
/// (one `ModelContext`).
public enum PeopleComposition {
    @MainActor
    public static func makeRepository(for context: ModelContext) -> PersonRepository {
        PersonRepository(context: context, now: { .now })
    }
}
