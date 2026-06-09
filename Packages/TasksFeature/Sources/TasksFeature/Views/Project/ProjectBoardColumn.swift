import Foundation
import NexusCore

/// One column of the Linear-style project board. A column is keyed by an
/// optional `WorkflowState`: the `nil` key is the "No Status" lane where a
/// project task that has not yet opted into the workflow machine lives
/// (`TaskItem.projectID != nil` but `workflowState == nil`). Dragging a card out
/// of the `nil` lane into any concrete column is exactly how a task opts in, via
/// the single sanctioned write path `TaskItemRepository.setWorkflowState`.
public struct ProjectBoardColumn: Identifiable {
    /// `nil` = the "No Status" lane (GTD / not-yet-opted-in project tasks).
    public let state: WorkflowState?
    public let tasks: [TaskItem]

    public var id: String { state?.rawValue ?? "__noStatus__" }

    public init(state: WorkflowState?, tasks: [TaskItem]) {
        self.state = state
        self.tasks = tasks
    }

    /// Human label for the column header.
    public var title: String {
        Self.title(for: state)
    }

    /// Human label for a column key (also used by the card's state pill).
    public static func title(for state: WorkflowState?) -> String {
        switch state {
        case .none: return "No Status"
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .done: return "Done"
        case .canceled: return "Canceled"
        case .duplicate: return "Duplicate"
        }
    }
}

/// The canonical left-to-right ordering of the board's primary columns. The two
/// terminal *non-completion* closures (`canceled`/`duplicate`) are intentionally
/// excluded from the primary lanes — they force `status = .done` without counting
/// as completed work (spec §5.2 I4), so they only appear as trailing collapsed
/// lanes when a task actually carries them (see `projectBoardColumns`).
public let projectBoardPrimaryStates: [WorkflowState?] = [
    nil,
    .backlog,
    .todo,
    .inProgress,
    .inReview,
    .done,
]

/// The trailing terminal-closure lanes, appended only when non-empty.
public let projectBoardTerminalStates: [WorkflowState] = [.canceled, .duplicate]

/// Pure bucketing seam (module-scope, not `@MainActor`, no SwiftUI) so the
/// board layout is unit-testable in isolation — mirrors the `taskNexusStatus`
/// testable-seam pattern in `TaskRowView`.
///
/// - Primary lanes (`No Status`/`Backlog`/`To Do`/`In Progress`/`In Review`/`Done`)
///   are ALWAYS present, even when empty, so the board is a stable grid.
/// - The terminal closures (`Canceled`/`Duplicate`) appear only when at least one
///   task carries them — they are noise otherwise.
/// - Within a lane, tasks keep the order they arrive in (callers pre-sort).
public func projectBoardColumns(for tasks: [TaskItem]) -> [ProjectBoardColumn] {
    var bucketed: [String: [TaskItem]] = [:]
    for task in tasks {
        let key = task.workflowState?.rawValue ?? "__noStatus__"
        bucketed[key, default: []].append(task)
    }

    var columns = projectBoardPrimaryStates.map { state -> ProjectBoardColumn in
        let key = state?.rawValue ?? "__noStatus__"
        return ProjectBoardColumn(state: state, tasks: bucketed[key] ?? [])
    }

    for terminal in projectBoardTerminalStates {
        let tasks = bucketed[terminal.rawValue] ?? []
        if !tasks.isEmpty {
            columns.append(ProjectBoardColumn(state: terminal, tasks: tasks))
        }
    }

    return columns
}
