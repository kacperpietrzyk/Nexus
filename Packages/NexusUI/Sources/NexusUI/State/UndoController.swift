import Observation
import SwiftUI

/// Drives a transient "Deleted N · Undo" toast.
///
/// A module fires `show(message:undo:)` right after a destructive action
/// (typically a soft-delete) and supplies the `undo` closure (usually a repo
/// restore / re-insert). The toast auto-dismisses after `duration` seconds; if
/// the user taps Undo first, the closure runs and the toast clears.
///
/// `dismiss()` and `performUndo()` are directly callable so the undo logic is
/// unit-testable without waiting on the auto-dismiss timer — only the timer
/// path calls `dismiss()`.
@MainActor
@Observable
public final class UndoController {

    /// The live toast, or `nil` when nothing is showing.
    public private(set) var current: Toast?

    /// Auto-dismiss delay in seconds.
    public let duration: Double

    private var dismissTask: Task<Void, Never>?
    private var token = 0

    public init(duration: Double = 5) {
        self.duration = duration
    }

    /// A single in-flight undoable action.
    public struct Toast: Identifiable {
        public let id = UUID()
        public let message: String
        public let icon: String
        let undo: () -> Void
    }

    /// Whether a toast is currently visible.
    public var isPresenting: Bool { current != nil }

    /// Shows the undo toast and (re)starts the auto-dismiss timer. Replaces any
    /// toast already on screen.
    ///
    /// - Parameters:
    ///   - message: the toast copy, e.g. `"Deleted 3"`.
    ///   - icon: leading SF Symbol (defaults to the undo arrow).
    ///   - undo: the action to run when the user taps Undo.
    public func show(
        message: String,
        icon: String = "arrow.uturn.backward",
        undo: @escaping () -> Void
    ) {
        token += 1
        let mine = token
        current = Toast(message: message, icon: icon, undo: undo)
        dismissTask?.cancel()
        dismissTask = Task { [duration] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            // Only auto-dismiss if no newer toast superseded this one.
            if self.token == mine { self.dismiss() }
        }
    }

    /// Runs the current toast's undo closure and clears the toast.
    public func performUndo() {
        guard let toast = current else { return }
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        toast.undo()
    }

    /// Clears the toast without running undo (auto-dismiss / manual close).
    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }
}

/// Presents the `UndoController`'s toast pinned to the bottom of the surface.
private struct UndoToastModifier: ViewModifier {
    @Bindable var controller: UndoController

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = controller.current {
                    Button {
                        withAnimation(DS.Motion.exit) { controller.performUndo() }
                    } label: {
                        NexusToast(icon: toast.icon, message: toast.message, undo: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, DS.Space.l)
                    .transition(.nexusToast)
                    .accessibilityLabel("\(toast.message). Undo")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .animation(DS.Motion.standard, value: controller.current?.id)
    }
}

extension View {
    /// Presents `controller`'s undo toast at the bottom of this surface. Tapping
    /// the toast runs the undo closure; otherwise it auto-dismisses.
    public func undoToast(_ controller: UndoController) -> some View {
        modifier(UndoToastModifier(controller: controller))
    }
}
