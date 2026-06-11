import NexusCore
import SwiftUI

/// Activity card, split out of `TaskDetailInspector.swift` to keep that file
/// under the 600-line budget. Mirrors the Comments extension pattern.
extension TaskDetailInspector {

    var activityCard: some View {
        inspectorCard("Activity") {
            ActivitySection(
                itemID: task.id,
                itemKind: .task,
                repository: ActivityEntryRepository(context: modelContext),
                projectName: { projectID in
                    let projects = ProjectRepository(context: modelContext, now: { .now })
                    return (try? projects.find(id: projectID))?.name
                },
                reloadToken: task.updatedAt
            )
        }
    }
}
