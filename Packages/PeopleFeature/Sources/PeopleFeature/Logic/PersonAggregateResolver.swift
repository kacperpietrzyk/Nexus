import Foundation
import NexusCore
import SwiftData

/// Resolves the raw graph endpoints from `PersonRepository.aggregate` into concrete
/// displayable rows (spec §6/§7). `TaskItem` and `Note` live in NexusCore so they
/// are fetched directly here; `Meeting` lives in NexusMeetings (un-importable) and
/// is resolved by the host via `PersonMeetingResolver`.
///
/// Extracted from the SwiftUI profile so the "everything about X" fetch — the
/// marquee §1 feature — is unit-testable against a real in-memory `ModelContext`.
/// Errors are surfaced via `throws` (the view decides how to present them) rather
/// than swallowed, so a failed fetch never silently renders an empty profile.
@MainActor
public enum PersonAggregateResolver {
    /// Fetches the live tasks for `ids`, newest-updated first. Uses an array
    /// `contains` predicate (more reliably translated by SwiftData than a captured
    /// `Set.contains`) and post-filters tombstones in memory.
    public static func resolveTasks(ids: [UUID], in context: ModelContext) throws -> [TaskItem] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return try context.fetch(descriptor)
            .filter { $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Fetches the live notes for `ids`, newest-updated first. See `resolveTasks`.
    public static func resolveNotes(ids: [UUID], in context: ModelContext) throws -> [Note] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return try context.fetch(descriptor)
            .filter { $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
