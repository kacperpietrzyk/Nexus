import NexusUI
import SwiftUI

// Layout bodies for `TaskDetailInspector`, split out of the main file to keep it
// under the file/type-length budget. `.column` is the single-column scroll
// (iOS sheet / pushed view); `.wide` is the 2-column, content-hugging layout the
// Mac centered modal uses so the dialog is short instead of a tall scroll.
extension TaskDetailInspector {

    @ViewBuilder
    var layoutBody: some View {
        switch layout {
        case .column:
            columnBody
        case .wide:
            wideBody
        }
    }

    /// Single-column scroll (iOS / pushed view).
    var columnBody: some View {
        ZStack {
            NexusWallpaper()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    headerCard
                    workflowCard
                    cycleCard
                    classificationCard
                    aiAssistCard
                    scheduleCard
                    deadlineCard
                    remindersCard
                    recurrenceCard
                    linksCard
                    promoteCard
                    templateCard
                    notesCard
                    commentsCard
                    activityCard
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// Two-column, content-hugging layout for the Mac centered modal. The same
    /// cards split into two balanced columns so the dialog is short (little/no
    /// vertical scroll). Wallpaper is a `.background` (does not drive sizing), so
    /// the host can size the modal to the content height.
    ///
    /// The full inline `linksCard` (which eagerly lists up to 8 parent/block
    /// candidates inline) stays on the `.column` layout; the modal uses the
    /// compact `linksCompactCard` (current relationships only; add-pickers in
    /// popovers) so it never grows the dialog.
    var wideBody: some View {
        // NO ScrollView: a plain HStack has an intrinsic height, so the host
        // modal sizes to the content (a short dialog, no phantom scrollbar). A
        // ScrollView would instead fill the host frame and show a scroll
        // indicator over empty space.
        VStack(spacing: 16) {
            // Two balanced metadata columns (header anchors the left, AI the
            // right); Notes spans full width below so neither column is dragged
            // tall by the editor and the two columns stay roughly even.
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    workflowCard
                    cycleCard
                    classificationCard
                    scheduleCard
                }
                VStack(alignment: .leading, spacing: 16) {
                    aiAssistCard
                    deadlineCard
                    remindersCard
                    recurrenceCard
                    promoteCard
                    templateCard
                }
            }
            // Notes + Links share a bottom row (side by side) so the dialog stays
            // short — stacking both full-width pushed the content past the window.
            HStack(alignment: .top, spacing: 16) {
                notesCard
                linksCompactCard
            }
            commentsCard
            activityCard
        }
        .padding(20)
        // Liquid re-skin: the wallpaper background is dropped — the Mac modal
        // host paints the liquid glass panel; an opaque wallpaper here would
        // occlude it. (Sizing is unaffected: a `.background` never drove it.)
    }
}
