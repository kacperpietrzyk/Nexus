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
    }

    /// Projects no longer mount a right inspector — Health/Risk/Activity now live
    /// in the Overview tab (`ProjectOverview`), so all Projects tabs render
    /// full-width. The 304 pt slot stays unused for this destination.
    var projectsInspectorSlot: (() -> AnyView)? { nil }
}
