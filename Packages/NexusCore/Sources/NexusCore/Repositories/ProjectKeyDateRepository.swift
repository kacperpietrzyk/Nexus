import Foundation
import SwiftData

/// Manages `ProjectKeyDate` anchor dates for a project (universal-types extension).
/// Bound to a single `ModelContext`; never share across actors. Upsert is keyed on
/// `(projectID, anchorKey)` so each anchor exists at most once per project.
@MainActor
public final class ProjectKeyDateRepository {
    public let context: ModelContext
    public let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    /// Creates or updates the anchor identified by `(projectID, anchorKey)`.
    @discardableResult
    public func setKeyDate(
        projectID: UUID,
        anchorKey: String,
        label: String,
        date: Date,
        isContractual: Bool = false
    ) throws -> ProjectKeyDate {
        // Pre-filter by projectID in SQLite, then refine anchorKey + deletedAt in-memory
        // (mirrors LinkRepository.findOrCreate pattern — compound #Predicate with optional
        // deletedAt and String equality triggers a Release-mode keypath trap).
        let candidates = try context.fetch(
            FetchDescriptor<ProjectKeyDate>(
                predicate: #Predicate { $0.projectID == projectID }
            )
        )
        if let existing = candidates.first(where: {
            $0.anchorKey == anchorKey && $0.deletedAt == nil
        }) {
            existing.label = label
            existing.date = date
            existing.isContractual = isContractual
            existing.updatedAt = now()
            try context.save()
            return existing
        }

        let keyDate = ProjectKeyDate(
            projectID: projectID,
            anchorKey: anchorKey,
            label: label,
            date: date,
            isContractual: isContractual
        )
        let stamp = now()
        keyDate.createdAt = stamp
        keyDate.updatedAt = stamp
        context.insert(keyDate)
        try context.save()
        return keyDate
    }

    /// Lists a project's anchors, soonest first, excluding soft-deleted.
    public func list(projectID: UUID) throws -> [ProjectKeyDate] {
        try context.fetch(
            FetchDescriptor<ProjectKeyDate>(
                predicate: #Predicate { $0.projectID == projectID }
            )
        )
        .filter { $0.deletedAt == nil }
        .sorted { $0.date < $1.date }
    }

    /// Soft-deletes the anchor identified by `(projectID, anchorKey)` if present.
    public func delete(projectID: UUID, anchorKey: String) throws {
        let candidates = try context.fetch(
            FetchDescriptor<ProjectKeyDate>(
                predicate: #Predicate { $0.projectID == projectID }
            )
        )
        guard
            let existing = candidates.first(where: {
                $0.anchorKey == anchorKey && $0.deletedAt == nil
            })
        else { return }
        let stamp = now()
        existing.deletedAt = stamp
        existing.updatedAt = stamp
        try context.save()
    }
}
