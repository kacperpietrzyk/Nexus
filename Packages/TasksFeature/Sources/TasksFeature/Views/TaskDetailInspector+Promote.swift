import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// "Promote to Project" action (Projects tier, spec §6 / item 6). Offered only for
/// a standalone complex task (`projectID == nil`) — a task that already lives in a
/// project is a phase, not a promotion candidate. The action runs the atomic
/// `ProjectPromoter.promoteToProject` (spec §6.1, invariant I6): the task becomes
/// the project's backing note, its children become phases, its graph edges
/// repoint, and the original is soft-deleted — so the inspector closes afterwards
/// (the task no longer exists).
extension TaskDetailInspector {

    /// A standalone task (not already a project phase) can be promoted.
    var canPromoteToProject: Bool { task.projectID == nil }

    @ViewBuilder
    var promoteCard: some View {
        if canPromoteToProject {
            inspectorCard("Project") {
                Text("Promote this task into a project. Its notes become the project page and its subtasks become phases.")
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textTertiary)

                NexusButton(
                    variant: .outline,
                    size: .md,
                    action: { promoteConfirmation = true },
                    label: { Label("Promote to Project", systemImage: "folder.badge.plus") }
                )
                .confirmationDialog(
                    "Promote to Project?",
                    isPresented: $promoteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Promote") { promoteToProject() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This converts the task into a project and removes the original task.")
                }

                if let promoteError {
                    Text(promoteError)
                        .font(.caption)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                }
            }
        }
    }

    @MainActor
    private func promoteToProject() {
        let promoter = ProjectPromoter(context: modelContext)
        do {
            _ = try promoter.promoteToProject(task)
            promoteError = nil
            onClose?()
        } catch {
            promoteError = "Couldn't promote this task to a project."
        }
    }
}
