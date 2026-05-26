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

        // User-facing copy is Polish — consistent with the rest of the app's
        // empty-state vocabulary (Today "Dzień czysty", the DZIEŃ rail's
        // "Brak zaplanowanych bloków", the capture bar's "Zapisz zadanie…").
        // The `.savedFilter` precedent renders English, but that is the
        // codebase outlier, not the rule; CLAUDE.md keeps code/comments/
        // commits English while user-facing UI copy follows the app language.
        switch filter {
        case .all:
            return .empty(
                title: "Brak zadań",
                systemImage: "tray",
                message: "Zapisz pierwsze zadanie — pojawi się tutaj."
            )
        case .today:
            return .empty(
                title: "Dzień czysty",
                systemImage: "checkmark.circle",
                message: "Nic zaległego, na dziś ani bez terminu."
            )
        case .upcoming:
            return .empty(
                title: "Nic na horyzoncie",
                systemImage: "calendar",
                message: "Brak zadań w najbliższych 7 dniach."
            )
        case .inbox:
            return .empty(
                title: "Inbox pusty",
                systemImage: "tray",
                message: "Brak nieposortowanych zadań."
            )
        case .completed:
            return .empty(
                title: "Nic ukończonego",
                systemImage: "checkmark.circle",
                message: "Ukończone zadania pojawią się tutaj."
            )
        case .byTag(let tag):
            return .empty(
                title: "Brak zadań z #\(tag)",
                systemImage: "tag",
                message: "Oznacz zadanie #\(tag), a pojawi się tutaj."
            )
        case .project:
            return .empty(
                title: "Brak zadań",
                systemImage: "folder",
                message: "Ten projekt nie ma otwartych zadań."
            )
        case .projectSection:
            return .empty(
                title: "Brak zadań",
                systemImage: "folder",
                message: "Ta sekcja nie ma otwartych zadań."
            )
        case .savedFilter:
            // Unreachable — handled above; kept for exhaustiveness.
            return .none
        }
    }
}
