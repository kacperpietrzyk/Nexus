import NexusCore
import SwiftUI

/// Comments card, split out of `TaskDetailInspector.swift` to keep that file
/// under the 600-line budget. Mirrors the Reminders extension pattern.
extension TaskDetailInspector {

    var commentsCard: some View {
        inspectorCard("Comments") {
            CommentsSection(
                itemID: task.id,
                itemKind: .task,
                repository: CommentRepository(context: modelContext)
            )
        }
    }
}
