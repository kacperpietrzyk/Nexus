import Foundation
import NexusCore
import SwiftData

@MainActor
enum ProjectSidebarAssignment {
    static func assign(
        payloads: [TaskItemDropPayload],
        projectID: UUID,
        sectionID: UUID?,
        modelContext: ModelContext,
        repository: TaskItemRepository
    ) throws -> Bool {
        var assignedAny = false
        for payload in payloads {
            guard let task = try task(id: payload.taskID, modelContext: modelContext) else { continue }
            try repository.assign(task, toProject: projectID, section: sectionID)
            assignedAny = true
        }
        return assignedAny
    }

    private static func task(id: UUID, modelContext: ModelContext) throws -> TaskItem? {
        let taskID = id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.id == taskID && task.deletedAt == nil
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}
