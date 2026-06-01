import NexusUI
import SwiftUI
import TasksFeature

// SUB-A (task-detail peek) + SUB-B (in-window Quick Capture) overlay surfaces,
// extracted out of `ContentView` so the composition-root view body stays under
// the length budget. Both are plain computed views composed back into
// `dashboardBody` via `.overlay`.
extension ContentView {

    /// SUB-A floating peek. Gated on the UNCHANGED `inspectorBinding` /
    /// `InspectorVisibility.shouldShowInspector(...)` predicate (so §1
    /// "inspector ⊥ Agent" still holds and its test is untouched). A fixed
    /// ~360-wide raised panel floats over the content's trailing edge with a
    /// small inset; the list behind stays fully interactive (no scrim). The
    /// `pop` shadow separates it. Slides in from trailing. `.tint(Text.primary)`
    /// keeps the inspector's native segmented Priority picker / DatePickers /
    /// Steppers / toggles achromatic — the main-window tint does NOT reach a
    /// detached overlay any more than it reached the old `.inspector`. Esc and
    /// the inner close button both clear `selectedTask`.
    @ViewBuilder
    var taskPeek: some View {
        if inspectorBinding.wrappedValue, let task = selectedTask {
            TaskDetailInspector(task: task, onClose: { selectedTask = nil })
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .background(NexusColor.Background.panel)
                .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                        .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
                )
                .nexusShadow(NexusShadow.pop)
                .tint(NexusColor.Text.primary)
                .padding(.trailing, 9)
                .padding(.bottom, 9)
                // Top inset clears the shell's ~52pt top-bar band (18/11 padding
                // + content) so the peek does NOT cover the trailing "New Task"
                // button / breadcrumbs while a task is selected.
                .padding(.top, 60)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// SUB-B in-window Quick Capture. A dimmed scrim (tap to dismiss) centered
    /// over which sits `CapturePane` in a raised card. It inherits `taskParser`
    /// + `taskRepository` from the Window root (NexusMacApp injects both),
    /// exactly like the command-palette overlay inherits its environment.
    /// ⌘⌃N + every in-app "New Task" trigger posts `.nexusOpenCapture`, handled
    /// by `dashboardBody`'s `.onReceive`. The deleted `CaptureWindowController`
    /// used to supply the outer chrome (`.nexusGlass`); the raised card replaces
    /// it. `CapturePane`'s macOS body owns its own `.padding(22)` + `.frame(600)`,
    /// so the card adds zero padding.
    @ViewBuilder
    var captureOverlay: some View {
        if capturePresented {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { capturePresented = false }
                .overlay {
                    NexusCard(.elev2, padding: 0) {
                        CapturePane(
                            mode: captureMode,
                            onSaved: { capturePresented = false },
                            onCancelled: { capturePresented = false }
                        )
                    }
                    .fixedSize()
                    .nexusShadow(NexusShadow.pop)
                }
        }
    }
}
