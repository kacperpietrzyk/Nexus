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
        .onChange(of: liquidProjectsModel.selectedProjectID, initial: true) { _, _ in
            updateProjectsCrumb()
        }
        // Re-derive the crumb when projects finish loading (cold deep-link race).
        // If a deep-link sets selectedProjectID before `projects` loads, the first
        // onChange above finds no name and leaves detailCrumb nil. Once the array
        // loads (count 0→N), this fires and fills the real name in.
        // No loop: updateProjectsCrumb only WRITES detailCrumb; it never mutates
        // selectedProjectID or projects.
        .onChange(of: liquidProjectsModel.projects.count) { _, _ in
            if liquidProjectsModel.selectedProjectID != nil {
                updateProjectsCrumb()
            }
        }
        // Consume pending deep-links staged by the sidebar or back/forward.
        // `initial: true` ensures a deep-link staged before this view mounts is
        // consumed on appear (not only on later changes).
        .onChange(of: navigator.pendingDeepLink, initial: true) { _, link in
            if case .project(let pid)? = link {
                liquidProjectsModel.selectedProjectID = pid
                // `selectedProject` (and the execution feeds) are resolved from
                // `selectedProjectID` only inside `reload()` — mutating the id
                // alone leaves the screen on its previous state. Mirror the
                // screen's own `select()`, which sets the id then reloads.
                liquidProjectsModel.reload(modelContext: modelContext)
                navigator.pendingDeepLink = nil
            }
        }
        .onAppear {
            // Breadcrumb "Projects" (popToRoot) must return to the grid. Setting
            // the id alone won't: `selectedProject` is a stored property cleared
            // only by `reload()` (→ `loadSelectedProject` sees a nil id). Reload
            // after clearing so the screen actually drops back to the picker.
            navigator.onPopToRoot = {
                liquidProjectsModel.selectedProjectID = nil
                liquidProjectsModel.reload(modelContext: modelContext)
            }
        }
    }

    /// Projects no longer mount a right inspector — Health/Risk/Activity now live
    /// in the Overview tab (`ProjectOverview`), so all Projects tabs render
    /// full-width. The 304 pt slot stays unused for this destination.
    var projectsInspectorSlot: (() -> AnyView)? { nil }

    /// Derives and publishes `navigator.detailCrumb` from the current selection.
    ///
    /// - If a project is selected AND its name is resolvable, sets the leaf crumb.
    /// - If nothing is selected, clears the crumb.
    /// - If a project is selected but `projects` hasn't loaded yet (name not
    ///   resolvable), leaves `detailCrumb` unchanged so a subsequent projects-load
    ///   onChange can fill it in (cold deep-link race).
    ///
    /// Loop-free: this function only WRITES `navigator.detailCrumb` and never
    /// mutates `liquidProjectsModel.selectedProjectID` or `liquidProjectsModel.projects`.
    @MainActor func updateProjectsCrumb() {
        guard let id = liquidProjectsModel.selectedProjectID else {
            navigator.detailCrumb = nil
            return
        }
        if let name = liquidProjectsModel.projects.first(where: { $0.id == id })?.name {
            navigator.detailCrumb = NavCrumb(id: "project:\(id)", label: name, isLeaf: true)
        }
        // If projects haven't loaded yet, leave detailCrumb as-is; the
        // `.onChange(of: liquidProjectsModel.projects.count)` will re-fire.
    }
}
