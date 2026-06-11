import Foundation

/// Pure decision for the `TaskListView` empty-state.
///
/// Before this, only `.savedFilter` rendered a `ContentUnavailableView`; every
/// other filter rendered an empty `List` with no header and no copy, so an
/// empty Tasks tab read as a broken screen (see the post-redesign visual
/// audit, finding A1). Extracted as a pure static — same precedent as
/// `TodayDashboardContentRoute.route(for:)` / `InspectorVisibility` — so the
/// per-filter mapping is unit-testable without driving SwiftUI.
///
/// Scope is deliberately minimal: it does NOT change the existing error path
/// (`errorRow` for non-savedFilter, `savedFilterContent` for savedFilter). A
/// load error returns `.none` so that pre-existing behaviour is byte-for-byte
/// untouched; the empty-state only fills the genuine "no rows, no error" gap.
public enum TaskListEmptyState: Equatable, Sendable {
    case none
    case empty(title: String, systemImage: String, message: String)

    public static func resolve(
        filter: TaskFilter,
        isEmpty: Bool,
        hasError: Bool
    ) -> TaskListEmptyState {
        // `.savedFilter` owns its own empty/error UI inside
        // `savedFilterContent` — do not double-handle it.
        if case .savedFilter = filter { return .none }
        // Keep the pre-existing `errorRow` path: a load failure must not be
        // shadowed by the celebratory empty-state.
        if hasError { return .none }
        guard isEmpty else { return .none }
        return emptyCopy(for: filter)
    }

    /// Per-filter empty copy, split out of `resolve` for the function-body
    /// lint budget. User-facing copy in English — consistent with the rest of
    /// the app's empty-state vocabulary (Today "All clear", the DAY rail's
    /// "No blocks scheduled", the capture bar's "What to add?").
    private static func emptyCopy(for filter: TaskFilter) -> TaskListEmptyState {
        switch filter {
        case .all:
            return .empty(
                title: "No tasks",
                systemImage: "tray",
                message: "Add your first task — it will appear here."
            )
        case .today:
            return .empty(
                title: "All clear",
                systemImage: "checkmark.circle",
                message: "Nothing overdue, due today, or without a date."
            )
        case .upcoming:
            return .empty(
                title: "Nothing on the horizon",
                systemImage: "calendar",
                message: "No tasks in the next 7 days."
            )
        case .inbox:
            return .empty(
                title: "Inbox empty",
                systemImage: "tray",
                message: "No unsorted tasks."
            )
        case .completed:
            return .empty(
                title: "Nothing completed",
                systemImage: "checkmark.circle",
                message: "Completed tasks will appear here."
            )
        case .byTag, .project, .projectSection, .templates, .cycle, .savedFilter:
            return scopedEmptyCopy(for: filter)
        }
    }

    /// Scoped-filter empty copy (tag/project/section/templates/cycle), split
    /// from `emptyCopy` for the function-body lint budget.
    private static func scopedEmptyCopy(for filter: TaskFilter) -> TaskListEmptyState {
        switch filter {
        case .byTag(let tag):
            return .empty(
                title: "No tasks with #\(tag)",
                systemImage: "tag",
                message: "Tag a task with #\(tag) and it will appear here."
            )
        case .project:
            return .empty(
                title: "No tasks",
                systemImage: "folder",
                message: "This project has no open tasks."
            )
        case .projectSection:
            return .empty(
                title: "No tasks",
                systemImage: "folder",
                message: "This section has no open tasks."
            )
        case .templates:
            return .empty(
                title: "No templates",
                systemImage: "doc.on.doc",
                message: "Save a task as a template and it will appear here."
            )
        case .cycle:
            return .empty(
                title: "No tasks in this cycle",
                systemImage: "arrow.triangle.2.circlepath",
                message: "Assign open tasks from the cycle planner."
            )
        default:
            return .none
        }
    }
}
