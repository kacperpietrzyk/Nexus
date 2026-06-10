import SwiftUI
import TasksFeature

// Liquid Projects / Execution composition (Task 8), extracted out of
// `ContentView` (file-length budget) alongside the Today and Calendar
// extensions. One shared `LiquidProjectsModel` (`@State` on `ContentView`)
// drives BOTH the main column (`LiquidProjectScreen`) and the right-inspector
// slot (`ProjectInspector`), so the board, table, and health/risk/activity
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
    }

    /// Right-inspector slot content for `.projects`; `nil` while the picker
    /// list is showing (no selected project → nothing to inspect) and on
    /// every other destination, so the 304 pt column disappears entirely.
    var projectsInspectorSlot: (() -> AnyView)? {
        guard selection == .projects, liquidProjectsModel.selectedProjectID != nil else { return nil }
        let model = liquidProjectsModel
        return {
            AnyView(
                ProjectInspector(
                    model: model,
                    onOpenTask: { self.openTask($0) }
                )
            )
        }
    }
}
