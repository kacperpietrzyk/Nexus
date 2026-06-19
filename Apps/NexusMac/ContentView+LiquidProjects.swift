import NexusUI
import SwiftUI
import TasksFeature

// Liquid Projects / Execution composition (Task 8), extracted out of
// `ContentView` (file-length budget) alongside the Today and Calendar
// extensions. One shared `LiquidProjectsModel` (`@State` on `ContentView`)
// drives the Projects screen (`LiquidProjectScreen`) and its Overview
// dashboard (`ProjectOverview`), so the board, table, and health/risk/activity
// cards render the same load — the same sharing shape as Liquid Today.
extension ContentView {

    /// The Liquid Projects main column, mounted by `destinationMain` for
    /// `.projects`. Opening a card/row routes through `openTask` (inspector ⊥
    /// Agent invariant preserved — same chokepoint the old root view used).
    var liquidProjectsMain: some View {
        LiquidProjectScreen(
            model: liquidProjectsModel,
            onOpenTask: { openTask($0) }
        )
        // Pin structural identity so `destinationMain` branch re-evaluations
        // never tear down the screen's internal @State (tab, drafts).
        .id(TodayNavSelection.projects)
        // Publish the detail crumb whenever the selection changes. The crumb is
        // DERIVED from selection (no loop — setting detailCrumb never sets
        // selectedProjectID). `onPopToRoot` lets the shell breadcrumb clear the
        // selection so the screen returns to the project list.
        .onChange(of: liquidProjectsModel.selectedProjectID, initial: true) { _, id in
            if let id, let name = liquidProjectsModel.projects.first(where: { $0.id == id })?.name {
                navigator.detailCrumb = NavCrumb(id: "project:\(id)", label: name, isLeaf: true)
            } else {
                navigator.detailCrumb = nil
            }
        }
        // Consume pending deep-links staged by the sidebar or back/forward.
        // `initial: true` ensures a deep-link staged before this view mounts is
        // consumed on appear (not only on later changes).
        .onChange(of: navigator.pendingDeepLink, initial: true) { _, link in
            if case .project(let pid)? = link {
                liquidProjectsModel.selectedProjectID = pid
                navigator.pendingDeepLink = nil
            }
        }
        .onAppear {
            navigator.onPopToRoot = { liquidProjectsModel.selectedProjectID = nil }
        }
    }

    /// Projects no longer mount a right inspector — Health/Risk/Activity now live
    /// in the Overview tab (`ProjectOverview`), so all Projects tabs render
    /// full-width. The 304 pt slot stays unused for this destination.
    var projectsInspectorSlot: (() -> AnyView)? { nil }
}
