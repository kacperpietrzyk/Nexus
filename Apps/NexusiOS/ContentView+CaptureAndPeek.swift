import NexusCore
import NexusUI
import SwiftUI
import TasksFeature

// Regular-width (iPad) overlay surfaces, extracted out of `ContentView` so the
// composition-root view body stays under the SwiftLint file-length budget.
// Both mirror the Mac `ContentView+CaptureAndPeek` recipe and are composed back
// into the regular shell's detail pane via `.overlay`. On compact width (iPhone)
// the equivalent surfaces are native `.sheet`s; these overlays are gated to
// `isRegularWidth` so the two presentations never coexist.
extension ContentView {

    /// Decision #2 (regular width): floating task-detail peek, mirroring the Mac
    /// `taskPeek` recipe verbatim — a fixed 360-wide raised panel over the
    /// detail's trailing edge, list stays full-width/interactive (no scrim),
    /// r3 clip + hairline + `pop` shadow, `.tint(Text.primary)` so the
    /// inspector's native controls stay achromatic, slide-in from trailing.
    /// Close clears `selectedTask`. Gated to regular width so it never shows
    /// alongside the compact `.sheet`.
    @ViewBuilder
    var taskPeek: some View {
        if isRegularWidth, let task = selectedTask {
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
                .padding(.vertical, 9)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// Decision #3 (regular width): in-app centered Quick Capture, mirroring the
    /// Mac `captureOverlay` — a dimmed scrim (tap to dismiss) with `CapturePane`
    /// inside a raised `NexusCard(.elev2)`. Reuses the same `CapturePane` the
    /// compact `CaptureSheet` wraps (the Morning Digest wrapper is compact-only).
    /// Gated to regular width.
    @ViewBuilder
    var captureOverlay: some View {
        if isRegularWidth, capturePresented {
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
                    .frame(maxWidth: 600)
                    .nexusShadow(NexusShadow.pop)
                    .padding(40)
                }
                .transition(.opacity)
        }
    }
}
