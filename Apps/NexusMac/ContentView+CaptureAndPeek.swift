import CommandPaletteShell
import NexusUI
import SwiftUI
import TasksFeature

// SUB-A (task-detail peek) + SUB-B (in-window Quick Capture) overlay surfaces,
// extracted out of `ContentView` so the composition-root view body stays under
// the length budget. Both are plain computed views composed back into
// `dashboardBody` via `.overlay`.
extension ContentView {

    /// The ⌘K command palette overlay. Extracted out of `ContentView` (file-length
    /// budget) alongside the other overlay surfaces. A blurred + dimmed scrim
    /// (tap-to-dismiss) under the `CommandPaletteView`, plus the same Escape fix
    /// the capture overlay uses.
    @ViewBuilder
    var commandPaletteOverlay: some View {
        if commandPalettePresented {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { commandPalettePresented = false }

                CommandPaletteView { commandPalettePresented = false }

                // Escape dismisses the palette. It must sit as a direct ZStack
                // sibling (NOT a nested `.overlay`, which failed to register the
                // key-equivalent): the focused search field's field editor swallows
                // Escape, so CommandPaletteView's own `.onKeyPress(.escape)` never
                // fires. A `.cancelAction` key-equivalent fires via
                // `performKeyEquivalent:` first. Kept in the tree at `.opacity(0)`
                // (NOT `.hidden()`, which drops the key-equivalent registration).
                Button("Dismiss palette") { commandPalettePresented = false }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Task detail as a CENTERED MODAL (replaces the old trailing ~360 peek,
    /// which was too narrow for the inspector's rich content — title, priority,
    /// AI assist, schedule, deadline, recurrence, tags, notes). A dimmed scrim
    /// (tap to dismiss) focuses a ~580-wide height-capped dialog over the list.
    ///
    /// Gated on the UNCHANGED `inspectorBinding` /
    /// `InspectorVisibility.shouldShowInspector(...)` predicate (so §1
    /// "inspector ⊥ Agent" still holds and its test is untouched). The hosted
    /// `TaskDetailInspector` is reused verbatim (all field logic + auto-save) and
    /// is shared with iOS, so its single-column internals are NOT reshaped here —
    /// only the container changes. It paints its own base background + wallpaper,
    /// clipped to the dialog's rounded rect, and scrolls internally past the cap.
    /// `.tint(Text.primary)` keeps its native segmented Priority picker /
    /// DatePickers / toggles achromatic. Escape closes via the inspector's own
    /// `.cancelAction` close button (no duplicate key-equivalent here); the scrim
    /// tap and the × both clear `selectedTask`.
    @ViewBuilder
    var taskModal: some View {
        if inspectorBinding.wrappedValue, let task = selectedTask {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = nil }

                    TaskDetailInspector(task: task, onClose: { selectedTask = nil }, layout: .wide)
                        .frame(width: 720)
                        // Hug the content height when short, cap + scroll when tall:
                        // `fixedSize` lets the wide ScrollView adopt its content
                        // height (so a simple task is a short dialog, not a tall
                        // stretched one), and `maxHeight` clamps it to the window so
                        // a link-heavy task scrolls inside the cap instead of
                        // overflowing past the title.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxHeight: max(240, geo.size.height - 80))
                        .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                                .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                        )
                        .nexusShadow(NexusShadow.pop)
                        .tint(NexusColor.Text.primary)
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
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
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { capturePresented = false }

                NexusCard(.elev2, padding: 0) {
                    CapturePane(
                        mode: captureMode,
                        onSaved: { capturePresented = false },
                        onCancelled: { capturePresented = false }
                    )
                }
                .fixedSize()
                .nexusShadow(NexusShadow.pop)

                // Escape dismisses the in-window capture overlay. This `.cancelAction`
                // key-equivalent fires via `performKeyEquivalent:` BEFORE the focused
                // input's field editor swallows Escape — which is why CapturePane's
                // own `.onKeyPress(.escape)` never fired here. Without it, Escape
                // bubbled to the `.hiddenTitleBar` main window and closed it, and
                // because `applicationShouldTerminateAfterLastWindowClosed` is true
                // that quit the whole app. Kept in the layout at `.opacity(0)` (NOT
                // `.hidden()`, which drops it from the tree so the key-equivalent
                // never registers) and behind the scrim, so it has no visible chrome.
                Button("Dismiss capture") { capturePresented = false }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}
