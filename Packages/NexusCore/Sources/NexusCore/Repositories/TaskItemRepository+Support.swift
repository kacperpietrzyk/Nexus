import Foundation
import SwiftData

// Support types split out of TaskItemRepository.swift (value-identical move)
// to keep the main file under the file-length budget — the Workflow/Subtasks
// extension precedent.

public enum ProjectSectionAssignmentError: Error, Equatable {
    case sectionRequiresProject(sectionID: UUID)
    case sectionNotFound(sectionID: UUID)
    case sectionProjectMismatch(sectionID: UUID, expectedProjectID: UUID, actualProjectID: UUID)
    case cannotReassignSectionToItself(sectionID: UUID)
}

struct TaskCompletionSideEffects {
    var cancelledTaskIDs = Set<UUID>()
    var scheduledTasks: [TaskItem] = []

    var isEmpty: Bool {
        cancelledTaskIDs.isEmpty && scheduledTasks.isEmpty
    }
}

@MainActor
enum ProjectSectionAssignmentValidator {
    static func validate(sectionID: UUID?, belongsTo projectID: UUID?, in context: ModelContext) throws {
        guard let sectionID else { return }
        guard let projectID else {
            throw ProjectSectionAssignmentError.sectionRequiresProject(sectionID: sectionID)
        }

        let descriptor = FetchDescriptor<Section>(
            predicate: #Predicate { section in
                section.id == sectionID && section.deletedAt == nil
            }
        )
        guard let section = try context.fetch(descriptor).first else {
            throw ProjectSectionAssignmentError.sectionNotFound(sectionID: sectionID)
        }
        guard section.projectID == projectID else {
            throw ProjectSectionAssignmentError.sectionProjectMismatch(
                sectionID: sectionID,
                expectedProjectID: projectID,
                actualProjectID: section.projectID
            )
        }
    }
}
