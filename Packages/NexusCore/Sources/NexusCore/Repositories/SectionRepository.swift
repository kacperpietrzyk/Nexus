import Foundation
import SwiftData

/// CRUD + ordering lifecycle for `Section`. Bound to a single `ModelContext`;
/// never share across actors.
@MainActor
public final class SectionRepository {
    public let context: ModelContext
    public let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    @discardableResult
    public func create(projectID: UUID, name: String) throws -> Section {
        let siblings = try sections(in: projectID)
        let orderIndex = OrderIndex.midpoint(prev: siblings.last?.orderIndex, next: nil)
        let stamp = now()
        let section = Section(projectID: projectID, name: name, orderIndex: orderIndex)
        section.createdAt = stamp
        section.updatedAt = stamp
        context.insert(section)
        try context.save()
        return section
    }

    public func rename(_ section: Section, to name: String) throws {
        section.name = name
        section.updatedAt = now()
        try context.save()
    }

    public func reorder(_ section: Section, after previous: Section?, before next: Section?) throws {
        section.orderIndex = OrderIndex.midpoint(prev: previous?.orderIndex, next: next?.orderIndex)
        section.updatedAt = now()
        try context.save()
    }

    public func delete(_ section: Section, reassignTasksTo destinationSectionID: UUID? = nil) throws {
        if destinationSectionID == section.id {
            throw ProjectSectionAssignmentError.cannotReassignSectionToItself(sectionID: section.id)
        }
        try ProjectSectionAssignmentValidator.validate(
            sectionID: destinationSectionID,
            belongsTo: section.projectID,
            in: context
        )
        let stamp = now()
        let sourceSectionID = section.id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.sectionID == sourceSectionID && task.deletedAt == nil
            }
        )
        for task in try context.fetch(descriptor) {
            task.projectID = section.projectID
            task.sectionID = destinationSectionID
            task.updatedAt = stamp
        }
        section.deletedAt = stamp
        section.updatedAt = stamp
        try context.save()
    }

    public func sections(in projectID: UUID) throws -> [Section] {
        let descriptor = FetchDescriptor<Section>(
            predicate: #Predicate { section in
                section.projectID == projectID && section.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return try context.fetch(descriptor)
    }
}
