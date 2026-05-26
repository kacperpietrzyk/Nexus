import Foundation
import NexusCore

enum TaskSubtaskActionError: Error, Equatable {
    case parentNotOpen(parentID: UUID)
    case parentIsSubtask(parentID: UUID)
}

extension TaskSubtaskActionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .parentNotOpen:
            "Done tasks cannot contain new open subtasks."
        case .parentIsSubtask:
            "Subtasks cannot have their own subtasks."
        }
    }
}

@MainActor
enum TaskSubtaskAction {
    static func createChild(
        under parent: TaskItem,
        repository: TaskItemRepository,
        title: String = "New subtask"
    ) throws -> TaskItem {
        guard parent.status == .open else {
            throw TaskSubtaskActionError.parentNotOpen(parentID: parent.id)
        }
        // Match the ParentTaskPickerSheet `canAssign` invariant: subtasks
        // themselves cannot become parents. Without this guard,
        // `AI Assist → Break into subtasks` invoked on a subtask would
        // silently create grandchildren that the picker would reject and
        // the SubtaskListView depth ceiling could clip.
        guard parent.parentTaskID == nil else {
            throw TaskSubtaskActionError.parentIsSubtask(parentID: parent.id)
        }

        let child = TaskItem(
            title: title,
            parentTaskID: parent.id,
            projectID: parent.projectID,
            sectionID: parent.sectionID
        )
        try repository.insert(child)
        return child
    }
}
