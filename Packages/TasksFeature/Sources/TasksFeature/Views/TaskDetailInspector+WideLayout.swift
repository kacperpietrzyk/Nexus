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
                    aiAssistCard
                    scheduleCard
                    deadlineCard
                    recurrenceCard
                    linksCard
                    notesCard
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
    /// `linksCard` (the relationship browser — parent/subtask/blocks, which lists
    /// every candidate task inline) is intentionally OMITTED here: it is what made
    /// the dialog tall and scroll-heavy. It remains in the `.column` layout. A
    /// compact link affordance for the modal is a follow-up.
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
                    scheduleCard
                }
                VStack(alignment: .leading, spacing: 16) {
                    aiAssistCard
                    deadlineCard
                    recurrenceCard
                }
            }
            notesCard
        }
        .padding(20)
        .background(NexusWallpaper())
    }
}
