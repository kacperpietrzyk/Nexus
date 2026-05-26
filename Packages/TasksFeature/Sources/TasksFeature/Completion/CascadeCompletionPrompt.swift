import NexusCore
import SwiftUI

/// Pending cascade confirmation surfaced by interactive completion attempts.
/// Created when `TaskCompletionAction.complete(_:repository:)` throws
/// `TaskItemRepositoryError.parentHasOpenSubtasks` for the task the user just
/// tapped. The owning view binds the optional to a `.confirmationDialog`.
public struct CascadeCompletionPrompt: Identifiable, Equatable {
    public let id: UUID
    public let task: TaskItem
    public let openCount: Int

    public init(task: TaskItem, openCount: Int) {
        self.id = task.id
        self.task = task
        self.openCount = openCount
    }

    public static func == (lhs: CascadeCompletionPrompt, rhs: CascadeCompletionPrompt) -> Bool {
        lhs.id == rhs.id && lhs.openCount == rhs.openCount
    }

    public var dialogTitle: String {
        if openCount == 1 {
            return "Complete this task and 1 subtask?"
        }
        return "Complete this task and \(openCount) subtasks?"
    }

    public var dialogMessage: String {
        "Marking this parent done will also close its open subtasks. This cannot be undone in bulk."
    }
}

extension View {
    /// Attaches a confirmation dialog that asks the user to approve cascade
    /// completion. When the user confirms, `onConfirm` runs the cascade; when
    /// the user cancels the binding is cleared and nothing happens.
    func cascadeCompletionConfirmation(
        _ prompt: Binding<CascadeCompletionPrompt?>,
        onConfirm: @escaping (CascadeCompletionPrompt) -> Void
    ) -> some View {
        confirmationDialog(
            prompt.wrappedValue?.dialogTitle ?? "",
            isPresented: Binding(
                get: { prompt.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        prompt.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: prompt.wrappedValue
        ) { value in
            Button("Complete all", role: .destructive) {
                onConfirm(value)
                prompt.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {
                prompt.wrappedValue = nil
            }
        } message: { value in
            Text(value.dialogMessage)
        }
    }
}
